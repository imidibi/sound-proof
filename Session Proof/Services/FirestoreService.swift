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
        let songRef = db.collection("projects").document(projectId).collection("songs").document()
        
        let data: [String: Any] = [
            "name": song.name,
            "artist": song.artist ?? "",
            "notes": song.notes ?? "",
            "status": song.status.rawValue,
            "sortOrder": song.sortOrder,
            "createdAt": Timestamp(date: song.createdAt),
            "updatedAt": Timestamp(date: song.updatedAt)
        ]
        
        try await songRef.setData(data)
        return songRef.documentID
    }
    
    func updateSong(projectId: String, songId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = Timestamp(date: Date())
        try await db.collection("projects").document(projectId)
            .collection("songs").document(songId)
            .updateData(updateData)
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
            "uploadedAt": Timestamp(date: Date())
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
            .updateData(["approvalStatus": status.rawValue])
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
        commentId: String,
        status: CommentStatus
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("comments").document(commentId)
            .updateData(["status": status.rawValue])
    }
    
    func listenToComments(
        projectId: String,
        mixId: String,
        onChange: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        return db.collection("projects").document(projectId)
            .collection("comments")
            .whereField("mixId", isEqualTo: mixId)
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
            "createdAt": Timestamp(date: reviewer.createdAt)
        ]
        
        if let invitationToken = reviewer.invitationToken {
            data["invitationToken"] = invitationToken
        }
        if let acceptedAt = reviewer.acceptedAt {
            data["acceptedAt"] = Timestamp(date: acceptedAt)
        }
        if let invitedAt = reviewer.invitedAt {
            data["invitedAt"] = Timestamp(date: invitedAt)
        }
        
        try await reviewerRef.setData(data)
    }
    
    func updateReviewer(
        projectId: String,
        reviewerId: String,
        data: [String: Any]
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .updateData(data)
    }
    
    func removeReviewer(
        projectId: String,
        reviewerId: String
    ) async throws {
        try await db.collection("projects").document(projectId)
            .collection("reviewers").document(reviewerId)
            .delete()
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
        let query = db.collection("organizations").whereField("memberIds", arrayContains: userId)
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        return (document.documentID, document.data())
    }
    
    func deleteOrganization(organizationId: String) async throws {
        try await db.collection("organizations").document(organizationId).delete()
    }
    
    // MARK: - Share Code
    
    private func generateShareCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No confusing chars like O/0, I/1
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}
