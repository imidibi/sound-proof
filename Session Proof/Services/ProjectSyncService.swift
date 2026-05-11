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
        guard let fileURL = mix.resolvedAssetURL else {
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
            
            // Update local mix with both URL and filename
            await MainActor.run {
                mix.assetURL = destinationURL
                mix.assetFileName = fileName
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
    
    // MARK: - Sync All User Projects from Cloud
    
    func syncUserProjectsFromCloud(
        userId: String,
        modelContext: ModelContext
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        print("🔄 Syncing projects from cloud for user: \(userId)")
        
        do {
            // Get all projects for this user from Firestore
            let cloudProjects = try await firestoreService.getUserProjects(userId: userId)
            print("📦 Found \(cloudProjects.count) projects in cloud")
            
            for (projectId, projectData) in cloudProjects {
                // Check if project already exists locally
                let descriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.firestoreId == projectId }
                )
                let existingProjects = try modelContext.fetch(descriptor)
                
                if existingProjects.isEmpty {
                    // Create new local project
                    print("✨ Creating new local project: \(projectData["name"] ?? "Unknown")")
                    
                    let project = Project(
                        name: projectData["name"] as? String ?? "Untitled",
                        clientName: projectData["clientName"] as? String,
                        ownerUserID: userId,
                        notes: projectData["notes"] as? String
                    )
                    
                    project.firestoreId = projectId
                    project.shareCode = projectData["shareCode"] as? String
                    project.isSynced = true
                    project.lastSyncedAt = Date()
                    
                    if let statusString = projectData["status"] as? String,
                       let status = ProjectStatus(rawValue: statusString) {
                        project.status = status
                    }
                    
                    modelContext.insert(project)
                    try modelContext.save()
                    
                    // Now sync songs for this project
                    try await syncProjectSongsFromCloud(
                        projectId: projectId,
                        project: project,
                        modelContext: modelContext
                    )
                } else {
                    print("✓ Project already exists locally: \(projectData["name"] ?? "Unknown")")
                    
                    // Still sync songs in case there are new ones
                    if let existingProject = existingProjects.first {
                        try await syncProjectSongsFromCloud(
                            projectId: projectId,
                            project: existingProject,
                            modelContext: modelContext
                        )
                    }
                }
            }
            
            print("✅ Finished syncing all projects")
            
        } catch {
            print("❌ Error syncing projects: \(error)")
            syncError = error.localizedDescription
            throw error
        }
    }
    
    private func syncProjectSongsFromCloud(
        projectId: String,
        project: Project,
        modelContext: ModelContext
    ) async throws {
        let cloudSongs = try await firestoreService.getProjectSongs(projectId: projectId)
        print("🎵 Found \(cloudSongs.count) songs for project")
        
        for (songId, songData) in cloudSongs {
            // Check if song already exists locally
            let descriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.firestoreId == songId }
            )
            let existingSongs = try modelContext.fetch(descriptor)
            
            if existingSongs.isEmpty {
                print("✨ Creating new local song: \(songData["name"] ?? "Unknown")")
                
                let song = Song(
                    name: songData["name"] as? String ?? "Untitled",
                    artist: songData["artist"] as? String,
                    notes: songData["notes"] as? String,
                    sortOrder: songData["sortOrder"] as? Int ?? 0
                )
                
                song.firestoreId = songId
                song.project = project
                
                if let statusString = songData["status"] as? String,
                   let status = SongStatus(rawValue: statusString) {
                    song.status = status
                }
                
                modelContext.insert(song)
                try modelContext.save()
                
                // Now sync mixes for this song
                try await syncSongMixesFromCloud(
                    projectId: projectId,
                    songId: songId,
                    song: song,
                    modelContext: modelContext
                )
            } else {
                print("✓ Song already exists locally: \(songData["name"] ?? "Unknown")")
                
                // Still sync mixes in case there are new ones
                if let existingSong = existingSongs.first {
                    try await syncSongMixesFromCloud(
                        projectId: projectId,
                        songId: songId,
                        song: existingSong,
                        modelContext: modelContext
                    )
                }
            }
        }
    }
    
    private func syncSongMixesFromCloud(
        projectId: String,
        songId: String,
        song: Song,
        modelContext: ModelContext
    ) async throws {
        let cloudMixes = try await firestoreService.getSongMixes(projectId: projectId, songId: songId)
        print("🎚️ Found \(cloudMixes.count) mixes for song")
        
        for (mixId, mixData) in cloudMixes {
            // Check if mix already exists locally
            let descriptor = FetchDescriptor<Mix>(
                predicate: #Predicate { $0.firestoreId == mixId }
            )
            let existingMixes = try modelContext.fetch(descriptor)
            
            if existingMixes.isEmpty {
                print("✨ Creating new local mix: \(mixData["name"] ?? "Unknown")")
                
                let mix = Mix(
                    name: mixData["name"] as? String ?? "Untitled",
                    versionNumber: mixData["versionNumber"] as? Int ?? 1,
                    duration: mixData["duration"] as? TimeInterval ?? 0,
                    sampleRate: mixData["sampleRate"] as? Double ?? 44100,
                    channels: mixData["channels"] as? Int ?? 2,
                    cloudURL: mixData["cloudURL"] as? String,
                    firestoreId: mixId,
                    isUploaded: true
                )
                
                if let statusString = mixData["approvalStatus"] as? String,
                   let status = MixStatus(rawValue: statusString) {
                    mix.approvalStatus = status
                }
                
                mix.song = song
                modelContext.insert(mix)
                try modelContext.save()
                
                print("📥 Mix metadata synced (audio will download on demand)")
            } else {
                print("✓ Mix already exists locally: \(mixData["name"] ?? "Unknown")")
            }
        }
    }
}
