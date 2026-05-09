//
//  ProjectSyncService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import Foundation
import SwiftData

@Observable
class ProjectSyncService {
    private let firestoreService: FirestoreService
    private let cloudStorageService: CloudStorageService
    private let authService: AuthenticationService
    
    var isSyncing = false
    var syncError: String?
    
    init(
        firestoreService: FirestoreService,
        cloudStorageService: CloudStorageService,
        authService: AuthenticationService
    ) {
        self.firestoreService = firestoreService
        self.cloudStorageService = cloudStorageService
        self.authService = authService
    }
    
    // MARK: - Create and Sync Project
    
    func createAndSyncProject(
        project: Project,
        modelContext: ModelContext
    ) async throws {
        guard let userId = authService.currentUser?.id else {
            throw NSError(domain: "ProjectSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Create project in Firestore
            let firestoreId = try await firestoreService.createProject(
                project: project,
                ownerUserId: userId
            )
            
            // Get the share code from Firestore
            if let projectData = try await firestoreService.getProject(projectId: firestoreId),
               let shareCode = projectData["shareCode"] as? String {
                
                // Update local project
                await MainActor.run {
                    project.firestoreId = firestoreId
                    project.shareCode = shareCode
                    project.isSynced = true
                    project.lastSyncedAt = Date()
                    
                    try? modelContext.save()
                }
            }
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Upload Mix to Cloud
    
    func uploadMix(
        mix: Mix,
        projectId: String,
        songId: String,
        modelContext: ModelContext
    ) async throws {
        guard let fileURL = mix.assetURL else {
            throw NSError(domain: "ProjectSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Mix has no local file"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Upload file to Firebase Storage
            let cloudURL = try await cloudStorageService.uploadMix(
                projectId: projectId,
                songId: songId,
                mixId: mix.id.uuidString,
                fileURL: fileURL
            )
            
            // Create mix metadata in Firestore
            let firestoreId = try await firestoreService.createMix(
                projectId: projectId,
                songId: songId,
                mix: mix,
                cloudURL: cloudURL
            )
            
            // Update local mix
            await MainActor.run {
                mix.cloudURL = cloudURL
                mix.firestoreId = firestoreId
                mix.isUploaded = true
                mix.uploadedAt = Date()
                
                try? modelContext.save()
            }
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Download Mix from Cloud
    
    func downloadMix(
        mix: Mix,
        modelContext: ModelContext
    ) async throws {
        guard let cloudURL = mix.cloudURL else {
            throw NSError(domain: "ProjectSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Mix has no cloud URL"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Create local destination
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(mix.id.uuidString).wav"
            let destinationURL = documentsPath.appendingPathComponent(fileName)
            
            // Download from Firebase Storage
            try await cloudStorageService.downloadMix(
                downloadURL: cloudURL,
                destinationURL: destinationURL
            )
            
            // Update local mix
            await MainActor.run {
                mix.assetURL = destinationURL
                try? modelContext.save()
            }
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Sync Song
    
    func syncSong(
        song: Song,
        projectId: String,
        modelContext: ModelContext
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let firestoreId = try await firestoreService.createSong(
                projectId: projectId,
                song: song
            )
            
            await MainActor.run {
                song.firestoreId = firestoreId
                try? modelContext.save()
            }
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Join Project by Share Code
    
    func joinProjectByShareCode(
        shareCode: String,
        modelContext: ModelContext
    ) async throws -> Project {
        guard let userId = authService.currentUser?.id else {
            throw NSError(domain: "ProjectSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Get project from Firestore
            guard let (firestoreId, projectData) = try await firestoreService.getProjectByShareCode(shareCode: shareCode) else {
                throw NSError(domain: "ProjectSync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Project not found with code: \(shareCode)"])
            }
            
            // Create local project
            let project = Project(
                name: projectData["name"] as? String ?? "Untitled Project",
                clientName: projectData["clientName"] as? String,
                ownerUserID: projectData["ownerUserId"] as? String ?? "",
                firestoreId: firestoreId,
                shareCode: shareCode,
                isSynced: true,
                lastSyncedAt: Date()
            )
            
            await MainActor.run {
                modelContext.insert(project)
                try? modelContext.save()
            }
            
            return project
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Sync Comment
    
    func syncComment(
        comment: Comment,
        projectId: String,
        songId: String,
        mixId: String,
        voiceNoteURL: URL? = nil
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            var cloudVoiceNoteURL: String?
            
            // Upload voice note if present
            if let voiceNoteURL = voiceNoteURL {
                cloudVoiceNoteURL = try await cloudStorageService.uploadVoiceNote(
                    projectId: projectId,
                    commentId: comment.id.uuidString,
                    fileURL: voiceNoteURL
                )
            }
            
            // Create comment in Firestore
            let _ = try await firestoreService.createComment(
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                comment: comment,
                voiceNoteURL: cloudVoiceNoteURL
            )
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
}
