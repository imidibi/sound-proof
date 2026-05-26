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
        // Get all projects and check their reviewers subcollections
        // This avoids needing a collection group index
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        print("🔍 Searching all projects for reviewers with email: \(normalizedEmail)")
        
        var results: [(projectId: String, reviewerId: String, data: [String: Any])] = []
        
        // Get all projects
        let projectsSnapshot = try await db.collection("projects").getDocuments()
        print("📁 Found \(projectsSnapshot.documents.count) total projects to check")
        
        // Check each project's reviewers subcollection
        for projectDoc in projectsSnapshot.documents {
            let projectId = projectDoc.documentID
            
            // Query reviewers in this specific project by email
            let reviewersQuery = db.collection("projects").document(projectId)
                .collection("reviewers")
                .whereField("email", isEqualTo: normalizedEmail)
            
            let reviewersSnapshot = try await reviewersQuery.getDocuments()
            
            // Add any matching reviewers to results
            for reviewerDoc in reviewersSnapshot.documents {
                print("✉️ Found reviewer in project \(projectId): \(reviewerDoc.documentID)")
                results.append((
                    projectId: projectId,
                    reviewerId: reviewerDoc.documentID,
                    data: reviewerDoc.data()
                ))
            }
        }
        
        print("📊 Total matching reviewers found: \(results.count)")
        return results
    }
    
    func getProjectsWhereUserIsReviewer(userId: String, userEmail: String) async throws -> [(id: String, data: [String: Any])] {
        print("🔍 Searching for projects where user \(userId) (\(userEmail)) is a reviewer")
        
        // Use findPendingInvitationsByEmail to get all reviewer records for this user
        // This works because it queries by email in each project's reviewers subcollection
        let reviewerRecords = try await findPendingInvitationsByEmail(email: userEmail)
        print("📧 Found \(reviewerRecords.count) reviewer record(s) with user's email")
        
        var projectsWithUser: [(id: String, data: [String: Any])] = []
        var processedProjectIds = Set<String>()
        
        // For each reviewer record, get the project data
        for record in reviewerRecords {
            let projectId = record.projectId
            
            // Skip if we've already processed this project
            guard !processedProjectIds.contains(projectId) else {
                continue
            }
            
            do {
                // Get the project document
                let projectDoc = try await db.collection("projects").document(projectId).getDocument()
                
                if projectDoc.exists, let projectData = projectDoc.data() {
                    let projectName = projectData["name"] as? String ?? "Unknown"
                    print("✅ Found project: \(projectName) (\(projectId))")
                    projectsWithUser.append((projectId, projectData))
                    processedProjectIds.insert(projectId)
                } else {
                    print("⚠️ Project \(projectId) not found or has no data")
                }
            } catch {
                print("⚠️ Error fetching project \(projectId): \(error.localizedDescription)")
            }
        }
        
        print("📦 Found \(projectsWithUser.count) projects where user is a reviewer")
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
        print("🔥 FirestoreService.createSong called")
        print("   - projectId: \(projectId)")
        print("   - song.name: \(song.name)")
        
        let songRef = db.collection("projects").document(projectId).collection("songs").document()
        
        print("   - Generated songRef.documentID: \(songRef.documentID)")
        print("   - Full path: projects/\(projectId)/songs/\(songRef.documentID)")
        
        let data: [String: Any] = [
            "name": song.name,
            "artist": song.artist ?? "",
            "notes": song.notes ?? "",
            "status": song.status.rawValue,
            "sortOrder": song.sortOrder,
            "createdAt": Timestamp(date: song.createdAt),
            "updatedAt": Timestamp(date: song.updatedAt)
        ]
        
        print("   - About to call setData with data: \(data)")
        try await songRef.setData(data)
        print("   - setData completed successfully")
        
        return songRef.documentID
    }
    
    func updateSong(projectId: String, songId: String, data: [String: Any]) async throws {
        print("🔥 FirestoreService.updateSong called")
        print("   - projectId: \(projectId)")
        print("   - songId: \(songId)")
        print("   - Full path: projects/\(projectId)/songs/\(songId)")
        print("   - data: \(data)")
        
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        
        print("   - About to call setData with merge: true")
        // Use setData with merge to create document if it doesn't exist
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .setData(updateData, merge: true)
        print("   - setData completed successfully")
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
        print("🔥 FirestoreService.songExists called")
        print("   - Checking path: projects/\(projectId)/songs/\(songId)")
        
        let snapshot = try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .getDocument()
        
        print("   - snapshot.exists: \(snapshot.exists)")
        print("   - snapshot.data: \(snapshot.data() ?? [:])")
        
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
                    print("❌ Error fetching approvals: \(error?.localizedDescription ?? "Unknown")")
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
                    print("Error fetching comments: \(error?.localizedDescription ?? "Unknown error")")
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
                    print("Error fetching reviewers: \(error?.localizedDescription ?? "Unknown error")")
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
        
        print("🔍 DEBUG: About to write reviewer to Firestore with data:")
        print("   displayName: \(data["displayName"] ?? "nil")")
        print("   email: \(data["email"] ?? "nil")")
        print("   userId: \(data["userId"] ?? "nil")")
        print("   role: \(data["role"] ?? "nil")")
        print("   inviteStatus: \(data["inviteStatus"] ?? "nil")")
        print("   isKeyApprover: \(data["isKeyApprover"] ?? "nil")")
        print("   Reviewer object inviteStatus: \(reviewer.inviteStatus.rawValue)")
        
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
            print("✅ Successfully wrote reviewer to Firestore at path: projects/\(projectId)/reviewers/\(reviewer.id.uuidString)")
            
            // Immediately verify the write by reading it back
            let verifyDoc = try await reviewerRef.getDocument()
            if verifyDoc.exists {
                print("✅ VERIFIED: Document exists in Firestore")
                if let verifyData = verifyDoc.data() {
                    print("   Fields in Firestore: \(verifyData.keys.sorted())")
                    print("   inviteStatus in Firestore: \(verifyData["inviteStatus"] ?? "MISSING")")
                }
            } else {
                print("❌ ERROR: Document does NOT exist in Firestore after write!")
            }
        } catch {
            print("❌ CRITICAL ERROR writing to Firestore: \(error)")
            print("   Error details: \(error.localizedDescription)")
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
            print("🔗 Creating userId-based reviewer document: \(userId)")
            
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
                
                print("✅ Created userId-based document for reviewer")
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
        print("🔍 Querying Firestore for organization with userId: \(userId)")
        let query = db.collection("organizations").whereField("memberIds", arrayContains: userId)
        let snapshot = try await query.getDocuments()
        
        print("📊 Query returned \(snapshot.documents.count) organization(s)")
        for doc in snapshot.documents {
            print("   - Found org: \(doc.documentID)")
            if let memberIds = doc.data()["memberIds"] as? [String] {
                print("     memberIds: \(memberIds)")
            }
        }
        
        guard let document = snapshot.documents.first else {
            print("⚠️ No organization document found")
            return nil
        }
        
        print("✅ Returning organization: \(document.documentID)")
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
