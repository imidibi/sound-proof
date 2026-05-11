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
            "clientName": project.clientName,
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
            .collection("comments").document()
        
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
    
    // MARK: - Share Code
    
    private func generateShareCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No confusing chars like O/0, I/1
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}
