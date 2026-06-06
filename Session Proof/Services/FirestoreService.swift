//
//  FirestoreService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import Foundation
import FirebaseFirestore

@Observable
class FirestoreService {
    private let db = Firestore.firestore()
    
    // MARK: - Project Sync
    
    func createProject(
        project: Project,
        ownerUserId: String
    ) async throws -> String {
        let projectRef = db.collection("projects").document()
        
        let data: [String: Any] = [
            "name": project.name,
            "clientName": project.clientName as Any,
            "ownerUserId": ownerUserId,
            "status": project.status.rawValue,
            "createdAt": Timestamp(date: project.createdAt),
            "updatedAt": Timestamp(date: project.updatedAt),
            "shareCode": generateShareCode()
        ]
        
        try await projectRef.setData(data)
        return projectRef.documentID
    }
    
    func updateProject(projectId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        try await db.collection("projects").document(projectId).updateData(updateData)
    }
    
    func archiveProject(projectId: String) async throws {
        let data: [String: Any] = [
            "status": "Archived",
            "isArchived": true,
            "archivedAt": Timestamp(date: Date())
        ]
        try await updateProject(projectId: projectId, data: data)
    }
    
    func deleteProject(projectId: String) async throws {
        Logger.debug("🗑️ Deleting project from Firestore: \(projectId)")
        
        // Delete all songs and their subcollections
        let songsSnapshot = try await db.collection("projects").document(projectId)
            .collection("songs")
            .getDocuments()
        
        for songDoc in songsSnapshot.documents {
            let songId = songDoc.documentID
            
            // Delete all mixes and their subcollections
            let mixesSnapshot = try await db.collection("projects").document(projectId)
                .collection("songs").document(songId)
                .collection("mixes")
                .getDocuments()
            
            for mixDoc in mixesSnapshot.documents {
                let mixId = mixDoc.documentID
                
                // Delete comments
                let commentsSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("mixes").document(mixId)
                    .collection("comments")
                    .getDocuments()
                
                for commentDoc in commentsSnapshot.documents {
                    try await commentDoc.reference.delete()
                }
                
                // Delete approvals
                let approvalsSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("mixes").document(mixId)
                    .collection("approvals")
                    .getDocuments()
                
                for approvalDoc in approvalsSnapshot.documents {
                    try await approvalDoc.reference.delete()
                }
                
                // Delete mix
                try await mixDoc.reference.delete()
            }
            
            // Delete song
            try await songDoc.reference.delete()
        }
        
        // Delete all reviewers
        let reviewersSnapshot = try await db.collection("projects").document(projectId)
            .collection("reviewers")
            .getDocuments()
        
        for reviewerDoc in reviewersSnapshot.documents {
            try await reviewerDoc.reference.delete()
        }
        
        // Finally, delete the project itself
        try await db.collection("projects").document(projectId).delete()
        
        Logger.debug("✅ Project deleted from Firestore: \(projectId)")
    }
    
    func reloadProject(projectId: String) async throws {
        let data: [String: Any] = [
            "status": "Draft",
            "isArchived": false,
            "archivedAt": NSNull()
        ]
        try await updateProject(projectId: projectId, data: data)
    }
    
    func getProject(projectId: String) async throws -> [String: Any]? {
        let document = try await db.collection("projects").document(projectId).getDocument()
        return document.data()
    }
    
    func getProjectByShareCode(shareCode: String) async throws -> (id: String, data: [String: Any])? {
        let query = db.collection("projects").whereField("shareCode", isEqualTo: shareCode)
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        return (document.documentID, document.data())
    }
    
    func getUserProjects(userId: String) async throws -> [(id: String, data: [String: Any])] {
        let query = db.collection("projects").whereField("ownerUserId", isEqualTo: userId)
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.map { document in
            (document.documentID, document.data())
        }
    }
    
    func getAllProjectIds() async throws -> [String] {
        let snapshot = try await db.collection("projects").getDocuments()
        return snapshot.documents.map { $0.documentID }
    }
    
    func findPendingInvitationsByEmail(email: String) async throws -> [(projectId: String, reviewerId: String, data: [String: Any])] {
        // Check the root-level pending_invitations collection
        // This allows unauthenticated users to check for invitations during signup
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        Logger.debug("🔍 Checking pending_invitations collection for email: \(normalizedEmail)")
        
        var results: [(projectId: String, reviewerId: String, data: [String: Any])] = []
        
        // Query pending_invitations by email (document ID is the email)
        let inviteRef = db.collection("pending_invitations").document(normalizedEmail)
        let inviteDoc = try await inviteRef.getDocument()
        
        if inviteDoc.exists, let data = inviteDoc.data() {
            if let projectId = data["projectId"] as? String,
               let reviewerId = data["reviewerId"] as? String {
                Logger.debug("✉️ Found PENDING invitation for project: \(projectId)")
                results.append((
                    projectId: projectId,
                    reviewerId: reviewerId,
                    data: data
                ))
            }
        } else {
            Logger.debug("📊 No pending invitations found for: \(normalizedEmail)")
        }
        
        Logger.debug("📊 Total pending invitations found: \(results.count)")
        return results
    }
    
    func getProjectsWhereUserIsReviewer(userId: String, userEmail: String) async throws -> [(id: String, data: [String: Any])] {
        Logger.debug("🔍 Searching for projects where user \(userId) (\(userEmail)) is a reviewer")
        Logger.debug("🔍 Using collection group query on 'reviewers' with userId field")
        
        // Use collection group query to find all reviewer documents with this userId
        // This searches across all projects' reviewers subcollections
        let reviewersQuery = db.collectionGroup("reviewers")
            .whereField("userId", isEqualTo: userId)
        
        Logger.debug("🔍 Executing collection group query...")
        let reviewersSnapshot = try await reviewersQuery.getDocuments()
        Logger.debug("📧 Found \(reviewersSnapshot.documents.count) reviewer record(s) with userId: \(userId)")
        
        // Log each reviewer document found
        for (index, doc) in reviewersSnapshot.documents.enumerated() {
            Logger.debug("📧 Reviewer #\(index + 1): path=\(doc.reference.path), data=\(doc.data())")
        }
        
        var projectsWithUser: [(id: String, data: [String: Any])] = []
        var processedProjectIds = Set<String>()
        
        // For each reviewer record, extract the project ID and get the project data
        for reviewerDoc in reviewersSnapshot.documents {
            // Extract projectId from the document path: projects/{projectId}/reviewers/{reviewerId}
            let pathComponents = reviewerDoc.reference.path.split(separator: "/")
            Logger.debug("🔍 Processing path: \(reviewerDoc.reference.path)")
            Logger.debug("🔍 Path components: \(pathComponents)")
            
            guard pathComponents.count >= 2,
                  pathComponents[0] == "projects",
                  let projectId = pathComponents.indices.contains(1) ? String(pathComponents[1]) : nil else {
                Logger.warning("⚠️ Could not extract projectId from path: \(reviewerDoc.reference.path)")
                continue
            }
            
            Logger.debug("✅ Extracted projectId: \(projectId)")
            
            // Skip if we've already processed this project
            guard !processedProjectIds.contains(projectId) else {
                Logger.debug("⏭️ Already processed project: \(projectId)")
                continue
            }
            
            do {
                // Get the project document
                Logger.debug("🔍 Fetching project document: \(projectId)")
                let projectDoc = try await db.collection("projects").document(projectId).getDocument()
                Logger.debug("🔍 Project exists: \(projectDoc.exists)")
                
                if projectDoc.exists, let projectData = projectDoc.data() {
                    let projectName = projectData["name"] as? String ?? "Unknown"
                    Logger.debug("✅ Project data retrieved: \(projectName)")
                    Logger.debug("   - ownerUserId: \(projectData["ownerUserId"] ?? "missing")")
                    Logger.debug("   - isArchived: \(projectData["isArchived"] ?? "not set")")
                    
                    // Skip archived projects for reviewers
                    let isArchived = projectData["isArchived"] as? Bool ?? false
                    if isArchived {
                        Logger.debug("⏭️ Skipping archived project: \(projectName) (\(projectId))")
                        processedProjectIds.insert(projectId)
                        continue
                    }
                    
                    Logger.debug("✅ Adding project to results: \(projectName) (\(projectId))")
                    projectsWithUser.append((projectId, projectData))
                    processedProjectIds.insert(projectId)
                } else {
                    Logger.warning("⚠️ Project \(projectId) not found or has no data")
                    Logger.debug("   - Document exists: \(projectDoc.exists)")
                }
            } catch {
                Logger.warning("⚠️ Error fetching project \(projectId): \(error.localizedDescription)")
                Logger.debug("   - Full error: \(error)")
            }
        }
        
        Logger.debug("📦 Found \(projectsWithUser.count) projects where user is a reviewer")
        return projectsWithUser
    }
    
    func getProjectSongs(projectId: String) async throws -> [(id: String, data: [String: Any])] {
        let snapshot = try await db.collection("projects")
            .document(projectId)
            .collection("songs")
            .getDocuments()
        
        return snapshot.documents.map { document in
            (document.documentID, document.data())
        }
    }
    
    func getSongMixes(projectId: String, songId: String) async throws -> [(id: String, data: [String: Any])] {
        let snapshot = try await db.collection("projects")
            .document(projectId)
            .collection("songs")
            .document(songId)
            .collection("mixes")
            .getDocuments()
        
        return snapshot.documents.map { document in
            (document.documentID, document.data())
        }
    }
    
    // MARK: - Song Sync
    
    func createSong(
        projectId: String,
        song: Song
    ) async throws -> String {
        Logger.debug("🔥 FirestoreService.createSong called")
        Logger.debug("   - projectId: \(projectId)")
        Logger.debug("   - song.name: \(song.name)")
        
        let songRef = db.collection("projects").document(projectId).collection("songs").document()
        
        Logger.debug("   - Generated songRef.documentID: \(songRef.documentID)")
        Logger.debug("   - Full path: projects/\(projectId)/songs/\(songRef.documentID)")
        
        let data: [String: Any] = [
            "name": song.name,
            "artist": song.artist ?? "",
            "notes": song.notes ?? "",
            "status": song.status.rawValue,
            "sortOrder": song.sortOrder,
            "createdAt": Timestamp(date: song.createdAt),
            "updatedAt": Timestamp(date: song.updatedAt)
        ]
        
        Logger.debug("   - About to call setData with data: \(data)")
        try await songRef.setData(data)
        Logger.debug("   - setData completed successfully")
        
        return songRef.documentID
    }
    
    func updateSong(projectId: String, songId: String, data: [String: Any]) async throws {
        Logger.debug("🔥 FirestoreService.updateSong called")
        Logger.debug("   - projectId: \(projectId)")
        Logger.debug("   - songId: \(songId)")
        Logger.debug("   - Full path: projects/\(projectId)/songs/\(songId)")
        Logger.debug("   - data: \(data)")
        
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        
        Logger.debug("   - About to call setData with merge: true")
        // Use setData with merge to create document if it doesn't exist
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .setData(updateData, merge: true)
        Logger.debug("   - setData completed successfully")
    }
    
    func archiveSong(projectId: String, songId: String) async throws {
        let data: [String: Any] = [
            "status": "Archived",
            "isArchived": true,
            "archivedAt": Timestamp(date: Date())
        ]
        try await updateSong(projectId: projectId, songId: songId, data: data)
    }
    
    func reloadSong(projectId: String, songId: String) async throws {
        let data: [String: Any] = [
            "status": "Draft",
            "isArchived": false,
            "archivedAt": NSNull()
        ]
        try await updateSong(projectId: projectId, songId: songId, data: data)
    }
    
    func songExists(projectId: String, songId: String) async throws -> Bool {
        Logger.debug("🔥 FirestoreService.songExists called")
        Logger.debug("   - Checking path: projects/\(projectId)/songs/\(songId)")
        
        let snapshot = try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .getDocument()
        
        Logger.debug("   - snapshot.exists: \(snapshot.exists)")
        Logger.debug("   - snapshot.data: \(snapshot.data() ?? [:])")
        
        return snapshot.exists
    }
    
    // MARK: - Mix Sync
    
    func createMix(
        projectId: String,
        songId: String,
        mix: Mix,
        cloudURL: String
    ) async throws -> String {
        let mixRef = db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document()
        
        let data: [String: Any] = [
            "name": mix.name,
            "versionNumber": mix.versionNumber,
            "cloudURL": cloudURL,
            "duration": mix.duration,
            "sampleRate": mix.sampleRate,
            "channels": mix.channels,
            "approvalStatus": mix.approvalStatus.rawValue,
            "notes": mix.notes ?? "",
            "uploadedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: mix.lastModifiedAt),
            "isDeleted": mix.isDeleted
        ]
        
        try await mixRef.setData(data)
        return mixRef.documentID
    }
    
    func updateMixStatus(
        projectId: String,
        songId: String,
        mixId: String,
        status: MixStatus
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .updateData([
                "approvalStatus": status.rawValue,
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    func updateMix(
        projectId: String,
        songId: String,
        mixId: String,
        mix: Mix
    ) async throws {
        let data: [String: Any] = [
            "name": mix.name,
            "versionNumber": mix.versionNumber,
            "duration": mix.duration,
            "sampleRate": mix.sampleRate,
            "channels": mix.channels,
            "approvalStatus": mix.approvalStatus.rawValue,
            "notes": mix.notes ?? "",
            "updatedAt": Timestamp(date: mix.lastModifiedAt),
            "isDeleted": mix.isDeleted
        ]
        
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .updateData(data)
    }
    
    func updateMix(
        projectId: String,
        songId: String,
        mixId: String,
        data: [String: Any]
    ) async throws {
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .updateData(updateData)
    }
    
    func deleteMix(
        projectId: String,
        songId: String,
        mixId: String
    ) async throws {
        // Soft delete - mark as deleted instead of removing document
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .updateData([
                "isDeleted": true,
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - Approval Sync
    
    func createOrUpdateApproval(
        projectId: String,
        songId: String,
        mixId: String,
        approval: Approval,
        reviewerUserId: String
    ) async throws -> String {
        // Use reviewerUserId as the document ID for easy lookup
        let approvalRef = db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("approvals").document(reviewerUserId)
        
        let data: [String: Any] = [
            "reviewerUserId": reviewerUserId,
            "status": approval.status.rawValue,
            "createdAt": Timestamp(date: approval.createdAt),
            "updatedAt": Timestamp(date: approval.updatedAt)
        ]
        
        try await approvalRef.setData(data, merge: true)
        return approvalRef.documentID
    }
    
    func getApprovals(
        projectId: String,
        songId: String,
        mixId: String
    ) async throws -> [(id: String, data: [String: Any])] {
        let snapshot = try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("approvals")
            .getDocuments()
        
        return snapshot.documents.map { ($0.documentID, $0.data()) }
    }
    
    func deleteApproval(
        projectId: String,
        songId: String,
        mixId: String,
        reviewerUserId: String
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("approvals").document(reviewerUserId)
            .delete()
    }
    
    func setupApprovalsListener(
        projectId: String,
        songId: String,
        mixId: String,
        onChange: @escaping ([[String: Any]]) -> Void
    ) -> ListenerRegistration {
        return db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("approvals")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    Logger.error("❌ Error fetching approvals: \(error?.localizedDescription ?? "Unknown")")
                    return
                }
                
                let approvalsData = documents.map { $0.data() }
                onChange(approvalsData)
            }
    }
    
    // MARK: - Comment Sync
    
    func createComment(
        projectId: String,
        songId: String,
        mixId: String,
        comment: Comment,
        voiceNoteURL: String? = nil
    ) async throws -> String {
        let commentRef = db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("comments").document(comment.id.uuidString)
        
        var data: [String: Any] = [
            "songId": songId,
            "mixId": mixId,
            "timestamp": comment.timestamp,
            "text": comment.text,
            "status": comment.status.rawValue,
            "authorId": comment.authorID,
            "authorName": comment.authorName,
            "createdAt": Timestamp(date: comment.createdAt)
        ]
        
        if let endTimestamp = comment.endTimestamp {
            data["endTimestamp"] = endTimestamp
        }
        
        if let voiceNoteURL = voiceNoteURL {
            data["voiceNoteURL"] = voiceNoteURL
        }
        
        try await commentRef.setData(data)
        return commentRef.documentID
    }
    
    func updateCommentStatus(
        projectId: String,
        songId: String,
        mixId: String,
        commentId: String,
        status: CommentStatus
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("comments").document(commentId)
            .updateData(["status": status.rawValue])
    }
    
    func listenToComments(
        projectId: String,
        songId: String,
        mixId: String,
        onChange: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        return db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .collection("mixes").document(mixId)
            .collection("comments")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    Logger.debug("Error fetching comments: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                onChange(documents)
            }
    }
    
    func listenToReviewers(
        projectId: String,
        onChange: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        return db.collection("projects").document(projectId)
            .collection("reviewers")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    Logger.debug("Error fetching reviewers: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                onChange(documents)
            }
    }
    
    // MARK: - Reviewer Management
    
    func addReviewer(
        projectId: String,
        reviewer: Reviewer
    ) async throws {
        let reviewerRef = db.collection("projects").document(projectId).collection("reviewers").document(reviewer.id.uuidString)
        
        var data: [String: Any] = [
            "displayName": reviewer.displayName,
            "email": reviewer.email.lowercased(),
            "userId": reviewer.userId as Any,
            "role": reviewer.role.rawValue,
            "inviteStatus": reviewer.inviteStatus.rawValue,
            "isKeyApprover": reviewer.isKeyApprover,
            "createdAt": Timestamp(date: reviewer.createdAt)
        ]
        
        Logger.debug("🔍 DEBUG: About to write reviewer to Firestore with data:")
        Logger.debug("   displayName: \(data["displayName"] ?? "nil")")
        Logger.debug("   email: \(data["email"] ?? "nil")")
        Logger.debug("   userId: \(data["userId"] ?? "nil")")
        Logger.debug("   role: \(data["role"] ?? "nil")")
        Logger.debug("   inviteStatus: \(data["inviteStatus"] ?? "nil")")
        Logger.debug("   isKeyApprover: \(data["isKeyApprover"] ?? "nil")")
        Logger.debug("   Reviewer object inviteStatus: \(reviewer.inviteStatus.rawValue)")
        
        if let invitationToken = reviewer.invitationToken {
            data["invitationToken"] = invitationToken
        }
        if let acceptedAt = reviewer.acceptedAt {
            data["acceptedAt"] = Timestamp(date: acceptedAt)
        }
        if let invitedAt = reviewer.invitedAt {
            data["invitedAt"] = Timestamp(date: invitedAt)
        }
        
        // Create the main reviewer document with UUID as ID
        do {
            try await reviewerRef.setData(data)
            Logger.debug("✅ Successfully wrote reviewer to Firestore at path: projects/\(projectId)/reviewers/\(reviewer.id.uuidString)")
            
            // If this is a pending invitation, also create a root-level pending_invitations document
            // This allows unauthenticated users to check for invitations during signup
            if reviewer.inviteStatus == .sent {
                let pendingInviteData: [String: Any] = [
                    "inviteeEmail": reviewer.email.lowercased(),
                    "projectId": projectId,
                    "reviewerId": reviewer.id.uuidString,
                    "displayName": reviewer.displayName,
                    "createdAt": Timestamp(date: reviewer.createdAt)
                ]
                
                // Use email as document ID for easy lookup
                let inviteRef = db.collection("pending_invitations").document(reviewer.email.lowercased())
                try await inviteRef.setData(pendingInviteData)
                Logger.debug("✅ Created pending_invitations document for: \(reviewer.email)")
            }
            
            // Immediately verify the write by reading it back
            let verifyDoc = try await reviewerRef.getDocument()
            if verifyDoc.exists {
                Logger.debug("✅ VERIFIED: Document exists in Firestore")
                if let verifyData = verifyDoc.data() {
                    Logger.debug("   Fields in Firestore: \(verifyData.keys.sorted())")
                    Logger.debug("   inviteStatus in Firestore: \(verifyData["inviteStatus"] ?? "MISSING")")
                }
            } else {
                Logger.error("❌ ERROR: Document does NOT exist in Firestore after write!")
            }
        } catch {
            Logger.error("❌ CRITICAL ERROR writing to Firestore: \(error)")
            Logger.debug("   Error details: \(error.localizedDescription)")
            throw error
        }
        
        // Also create a document with userId as ID for Firestore rules to work
        // This allows isProjectReviewer() to check exists(/reviewers/$(request.auth.uid))
        if let userId = reviewer.userId {
            let userIdRef = db.collection("projects").document(projectId).collection("reviewers").document(userId)
            var userIdData = data
            userIdData["primaryReviewerId"] = reviewer.id.uuidString  // Reference to the main document
            try await userIdRef.setData(userIdData)
        }
    }
    
    func updateReviewer(
        projectId: String,
        reviewerId: String,
        data: [String: Any]
    ) async throws {
        // Update the main reviewer document
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .updateData(data)
        
        // If we're setting a userId, also create/update the userId-based document
        if let userId = data["userId"] as? String {
            Logger.debug("🔗 Creating userId-based reviewer document: \(userId)")
            
            // Get the current reviewer data to merge with updates
            let reviewerDoc = try await db.collection("projects").document(projectId)
                .collection("reviewers").document(reviewerId)
                .getDocument()
            
            if var reviewerData = reviewerDoc.data() {
                // Merge the updates into existing data
                for (key, value) in data {
                    reviewerData[key] = value
                }
                
                // Add reference to primary document
                reviewerData["primaryReviewerId"] = reviewerId
                
                // Create/update the userId-based document
                try await db.collection("projects").document(projectId)
                    .collection("reviewers").document(userId)
                    .setData(reviewerData)
                
                Logger.debug("✅ Created userId-based document for reviewer")
            }
        }
    }
    
    func removeReviewer(
        projectId: String,
        reviewerId: String
    ) async throws {
        // Get the reviewer document first to find the userId
        let reviewerDoc = try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .getDocument()
        
        // Delete the main reviewer document
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .delete()
        
        // Also delete the userId-based document if it exists
        if let userId = reviewerDoc.data()?["userId"] as? String {
            try? await db.collection("projects").document(projectId)
                .collection("reviewers").document(userId)
                .delete()
        }
    }
    
    func updateReviewerKeyApproverStatus(
        projectId: String,
        reviewerId: String,
        isKeyApprover: Bool
    ) async throws {
        // Update the main reviewer document
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .updateData(["isKeyApprover": isKeyApprover])
        
        // Also update the userId-based document if it exists
        let reviewerDoc = try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .getDocument()
        
        if let userId = reviewerDoc.data()?["userId"] as? String {
            try? await db.collection("projects").document(projectId)
                .collection("reviewers").document(userId)
                .updateData(["isKeyApprover": isKeyApprover])
        }
    }
    
    func updateReviewer(
        projectId: String,
        reviewer: Reviewer
    ) async throws {
        let data: [String: Any] = [
            "displayName": reviewer.displayName,
            "email": reviewer.email.lowercased(),
            "role": reviewer.role.rawValue
        ]
        
        // Update the main reviewer document
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewer.id.uuidString)
            .updateData(data)
        
        // Also update the userId-based document if it exists
        if let userId = reviewer.userId {
            try? await db.collection("projects").document(projectId)
                .collection("reviewers").document(userId)
                .updateData(data)
        }
    }
    
    func updateReviewerField(
        projectId: String,
        reviewerId: String,
        field: String,
        value: Any
    ) async throws {
        // Update the main reviewer document
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .updateData([field: value])
        
        // Also try to update the userId-based document if it exists
        // First get the reviewer to find the userId
        let reviewerDoc = try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .getDocument()
        
        if let userId = reviewerDoc.data()?["userId"] as? String {
            try? await db.collection("projects").document(projectId)
                .collection("reviewers").document(userId)
                .updateData([field: value])
        }
    }
    
    func getProjectReviewers(projectId: String) async throws -> [(id: String, data: [String: Any])] {
        let snapshot = try await db.collection("projects")
            .document(projectId)
            .collection("reviewers")
            .getDocuments()
        
        return snapshot.documents.map { document in
            (document.documentID, document.data())
        }
    }
    
    func findReviewerByToken(invitationToken: String) async throws -> (projectId: String, reviewerId: String, data: [String: Any])? {
        // Query across all projects to find the reviewer with this token
        let projectsSnapshot = try await db.collection("projects").getDocuments()
        
        for projectDoc in projectsSnapshot.documents {
            let reviewersSnapshot = try await db.collection("projects")
                .document(projectDoc.documentID)
                .collection("reviewers")
                .whereField("invitationToken", isEqualTo: invitationToken)
                .getDocuments()
            
            if let reviewerDoc = reviewersSnapshot.documents.first {
                return (projectDoc.documentID, reviewerDoc.documentID, reviewerDoc.data())
            }
        }
        
        return nil
    }
    
    func findReviewerByEmail(email: String, projectId: String) async throws -> (id: String, data: [String: Any])? {
        let snapshot = try await db.collection("projects")
            .document(projectId)
            .collection("reviewers")
            .whereField("email", isEqualTo: email.lowercased())
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        return (document.documentID, document.data())
    }
    
    func getAllReviewersForProducer(userId: String) async throws -> [(email: String, name: String, projectCount: Int)] {
        // Get all projects owned by this user
        let projects = try await getUserProjects(userId: userId)
        
        var reviewerMap: [String: (name: String, count: Int)] = [:]
        
        for (projectId, _) in projects {
            let reviewers = try await getProjectReviewers(projectId: projectId)
            
            for (_, reviewerData) in reviewers {
                if let email = reviewerData["email"] as? String,
                   let name = reviewerData["displayName"] as? String {
                    // Don't include owner themselves
                    if reviewerData["role"] as? String != "Owner" {
                        if var existing = reviewerMap[email] {
                            existing.count += 1
                            reviewerMap[email] = existing
                        } else {
                            reviewerMap[email] = (name, 1)
                        }
                    }
                }
            }
        }
        
        return reviewerMap.map { (email: $0.key, name: $0.value.name, projectCount: $0.value.count) }
            .sorted { $0.projectCount > $1.projectCount } // Most frequent first
    }
    
    // MARK: - FCM Token Management
    
    /// Add or update FCM token for a device
    /// Stores tokens in an array to support multiple devices per user
    func updateUserFCMToken(userId: String, fcmToken: String) async throws {
        // Use arrayUnion to add token only if it doesn't already exist
        try await db.collection("users").document(userId).updateData([
            "fcmTokens": FieldValue.arrayUnion([fcmToken]),
            "fcmTokensUpdatedAt": Timestamp(date: Date())
        ])
    }
    
    /// Remove a specific FCM token (when user signs out on one device)
    func deleteUserFCMToken(userId: String, fcmToken: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "fcmTokens": FieldValue.arrayRemove([fcmToken]),
            "fcmTokensUpdatedAt": Timestamp(date: Date())
        ])
    }
    
    /// Get all FCM tokens for a user (all their devices)
    func getUserFCMTokens(userId: String) async throws -> [String] {
        let document = try await db.collection("users").document(userId).getDocument()
        return document.data()?["fcmTokens"] as? [String] ?? []
    }
    
    /// Legacy method for backward compatibility - returns first token
    func getUserFCMToken(userId: String) async throws -> String? {
        let tokens = try await getUserFCMTokens(userId: userId)
        return tokens.first
    }
    
    // MARK: - Organization Management
    
    func createOrganization(
        organization: Organization,
        userId: String
    ) async throws -> String {
        let orgRef = db.collection("organizations").document(organization.id.uuidString)
        
        var data: [String: Any] = [
            "name": organization.name,
            "type": organization.type.rawValue,
            "maxProducers": organization.maxProducers,
            "isActive": organization.isActive,
            "createdAt": Timestamp(date: organization.createdAt),
            "updatedAt": Timestamp(date: organization.updatedAt),
            "memberIds": organization.memberIds
        ]
        
        // Add optional fields if they have values
        if let address = organization.address {
            data["address"] = address
        }
        if let city = organization.city {
            data["city"] = city
        }
        if let state = organization.state {
            data["state"] = state
        }
        if let zipCode = organization.zipCode {
            data["zipCode"] = zipCode
        }
        if let country = organization.country {
            data["country"] = country
        }
        if let phone = organization.phone {
            data["phone"] = phone
        }
        if let email = organization.email {
            data["email"] = email
        }
        if let website = organization.website {
            data["website"] = website
        }
        if let taxId = organization.taxId {
            data["taxId"] = taxId
        }
        if let notes = organization.notes {
            data["notes"] = notes
        }
        if let licenseType = organization.licenseType {
            data["licenseType"] = licenseType
        }
        if let licenseStartDate = organization.licenseStartDate {
            data["licenseStartDate"] = Timestamp(date: licenseStartDate)
        }
        if let licenseExpiryDate = organization.licenseExpiryDate {
            data["licenseExpiryDate"] = Timestamp(date: licenseExpiryDate)
        }
        
        try await orgRef.setData(data)
        return orgRef.documentID
    }
    
    func updateOrganization(organizationId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        try await db.collection("organizations").document(organizationId).updateData(updateData)
    }
    
    func getOrganization(organizationId: String) async throws -> [String: Any]? {
        let document = try await db.collection("organizations").document(organizationId).getDocument()
        return document.data()
    }
    
    func getUserOrganization(userId: String) async throws -> (id: String, data: [String: Any])? {
        Logger.debug("🔍 Querying Firestore for organization with userId: \(userId)")
        let query = db.collection("organizations").whereField("memberIds", arrayContains: userId)
        let snapshot = try await query.getDocuments()
        
        Logger.debug("📊 Query returned \(snapshot.documents.count) organization(s)")
        for doc in snapshot.documents {
            Logger.debug("   - Found org: \(doc.documentID)")
            if let memberIds = doc.data()["memberIds"] as? [String] {
                Logger.debug("     memberIds: \(memberIds)")
            }
        }
        
        guard let document = snapshot.documents.first else {
            Logger.warning("⚠️ No organization document found")
            return nil
        }
        
        Logger.debug("✅ Returning organization: \(document.documentID)")
        return (document.documentID, document.data())
    }
    
    func deleteOrganization(organizationId: String) async throws {
        try await db.collection("organizations").document(organizationId).delete()
    }
    
    // MARK: - Share Code
    // DEPRECATED: Share code functionality disabled - use email invitations only
    
    private func generateShareCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No confusing chars like O/0, I/1
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}
