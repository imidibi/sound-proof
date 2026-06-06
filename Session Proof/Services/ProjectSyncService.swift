//
//  ProjectSyncService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import Foundation
import SwiftData
import FirebaseFirestore

@Observable
class ProjectSyncService {
    private let firestoreService: FirestoreService
    private let cloudStorageService: CloudStorageService
    private let authService: AuthenticationService
    var inAppNotificationService: InAppNotificationService?
    
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
            
            // Always set firestoreId immediately to prevent duplicates
            await MainActor.run {
                project.firestoreId = firestoreId
                project.isSynced = true
                project.lastSyncedAt = Date()
            }
            
            // Get the share code from Firestore
            if let projectData = try await firestoreService.getProject(projectId: firestoreId),
               let shareCode = projectData["shareCode"] as? String {
                
                // Update local project with share code
                await MainActor.run {
                    project.shareCode = shareCode
                    try? modelContext.save()
                }
            } else {
                // Even if we couldn't get the share code, save the firestoreId
                await MainActor.run {
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
        // Only producers and studios can upload mixes
        guard authService.currentUser?.isProducer == true else {
            throw NSError(domain: "ProjectSync", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only producers can create mixes"])
        }
        
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
                mix.needsUpload = false  // Successfully uploaded
                mix.lastModifiedAt = Date()

                try? modelContext.save()
            }

        } catch {
            // Mark for retry on next sync
            await MainActor.run {
                mix.needsUpload = true
                try? modelContext.save()
            }

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
                song.needsUpload = false
                song.lastSyncedAt = Date()
                try? modelContext.save()
            }
            
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Join Project by Share Code
    // DEPRECATED: Share code functionality disabled - use email invitations only
    
    func joinProjectByShareCode(
        shareCode: String,
        modelContext: ModelContext
    ) async throws -> Project {
        guard authService.currentUser?.id != nil else {
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
            
            // Create reviewer entry for the joining user
            guard let currentUser = authService.currentUser else {
                throw NSError(domain: "ProjectSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
            }
            
            let reviewer = Reviewer(
                displayName: currentUser.displayName,
                email: currentUser.email,
                userId: currentUser.id,
                role: .reviewer,
                inviteStatus: .accepted,
                acceptedAt: Date()
            )
            reviewer.project = project
            
            await MainActor.run {
                modelContext.insert(project)
                modelContext.insert(reviewer)
                try? modelContext.save()
            }
            
            // Add reviewer to Firestore
            try await firestoreService.addReviewer(
                projectId: firestoreId,
                reviewer: reviewer
            )
            
            // Sync existing reviewers from Firestore
            try await syncProjectReviewers(
                projectId: firestoreId,
                project: project,
                modelContext: modelContext
            )
            
            // Sync songs and mixes from Firestore
            try await syncProjectSongsFromCloud(
                projectId: firestoreId,
                project: project,
                modelContext: modelContext
            )
            
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
    
    // MARK: - Listen to Comments
    
    func startListeningToComments(
        projectId: String,
        mixId: String,
        mix: Mix,
        modelContext: ModelContext
    ) -> FirebaseFirestore.ListenerRegistration {
        Logger.debug("👂 Setting up comment listener for project: \(projectId), mix: \(mixId)")
        
        // Get songId from mix's song relationship
        guard let song = mix.song, let songId = song.firestoreId else {
            Logger.warning("⚠️ Cannot set up comment listener: mix has no song or song has no firestoreId")
            // Return a dummy listener that does nothing
            return firestoreService.listenToComments(projectId: "", songId: "", mixId: "") { _ in }
        }
        
        return firestoreService.listenToComments(projectId: projectId, songId: songId, mixId: mixId) { [weak self] documents in
            guard let self = self else { return }
            
            Logger.debug("📬 Received \(documents.count) comment documents from Firestore")
            
            Task { @MainActor in
                for document in documents {
                    await self.processCommentFromCloud(
                        document: document,
                        mix: mix,
                        modelContext: modelContext
                    )
                }
            }
        }
    }
    
    private func processCommentFromCloud(
        document: FirebaseFirestore.QueryDocumentSnapshot,
        mix: Mix,
        modelContext: ModelContext
    ) async {
        let data = document.data()
        let commentId = document.documentID
        
        // Convert commentId string to UUID
        guard let commentUUID = UUID(uuidString: commentId) else {
            Logger.warning("⚠️ Skipping comment with invalid UUID format: \(commentId)")
            return
        }
        
        Logger.debug("📥 Processing comment from cloud: \(commentId)")
        
        // Check if comment already exists locally
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { comment in
                comment.id == commentUUID
            }
        )
        
        do {
            let existingComments = try modelContext.fetch(descriptor)
            
            if existingComments.isEmpty {
                // Create new local comment
                guard let timestamp = data["timestamp"] as? TimeInterval,
                      let text = data["text"] as? String,
                      let authorID = data["authorId"] as? String,
                      let authorName = data["authorName"] as? String else {
                    Logger.warning("⚠️ Invalid comment data for \(commentId)")
                    Logger.debug("   - timestamp: \(data["timestamp"] ?? "missing")")
                    Logger.debug("   - text: \(data["text"] ?? "missing")")
                    Logger.debug("   - authorId: \(data["authorId"] ?? "missing")")
                    Logger.debug("   - authorName: \(data["authorName"] ?? "missing")")
                    Logger.debug("   - Available keys: \(data.keys.joined(separator: ", "))")
                    return
                }
                
                let comment = Comment(
                    id: commentUUID,
                    timestamp: timestamp,
                    endTimestamp: data["endTimestamp"] as? TimeInterval,
                    text: text,
                    voiceNoteURL: nil,
                    voiceNoteFileName: nil,
                    voiceNoteCloudURL: data["voiceNoteURL"] as? String,
                    authorID: authorID,
                    authorName: authorName,
                    needsSync: false  // Already synced from cloud
                )
                
                if let statusString = data["status"] as? String,
                   let status = CommentStatus(rawValue: statusString) {
                    comment.status = status
                }
                
                // Handle voice note if present
                if let voiceNoteCloudURL = data["voiceNoteURL"] as? String {
                    // Download voice note in background
                    Task {
                        await downloadVoiceNote(
                            cloudURL: voiceNoteCloudURL,
                            commentId: commentId,
                            comment: comment
                        )
                    }
                }
                
                comment.mix = mix
                if let song = mix.song {
                    comment.song = song
                }
                
                modelContext.insert(comment)
                
                do {
                    try modelContext.save()
                    Logger.debug("✅ Comment synced from cloud: \(text.prefix(30))...")
                } catch {
                    Logger.error("❌ Failed to save comment: \(error)")
                }
            }
        } catch {
            Logger.error("❌ Error checking for existing comment: \(error)")
        }
    }
    
    // Public method for downloading voice notes on demand
    func downloadMissingVoiceNote(for comment: Comment) async -> Bool {
        guard let cloudURL = comment.voiceNoteCloudURL else {
            Logger.warning("⚠️ No cloud URL available for voice note")
            return false
        }
        
        let commentId = comment.id.uuidString
        await downloadVoiceNote(cloudURL: cloudURL, commentId: commentId, comment: comment)
        
        // Check if download was successful
        if let fileName = comment.voiceNoteFileName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localURL = documentsPath.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: localURL.path)
        }
        
        return false
    }
    
    private func downloadVoiceNote(
        cloudURL: String,
        commentId: String,
        comment: Comment
    ) async {
        do {
            // Download to documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "voice_note_\(commentId).m4a"
            let localURL = documentsPath.appendingPathComponent(fileName)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: localURL.path) {
                comment.voiceNoteFileName = fileName
                return
            }
            
            // Download from cloud storage
            guard let url = URL(string: cloudURL) else {
                Logger.warning("⚠️ Invalid voice note URL")
                return
            }
            
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            
            await MainActor.run {
                comment.voiceNoteFileName = fileName
                Logger.debug("✅ Voice note downloaded: \(fileName)")
            }
        } catch {
            Logger.error("❌ Failed to download voice note: \(error)")
        }
    }
    
    // MARK: - Sync All User Projects from Cloud
    
    func syncUserProjectsFromCloud(
        userId: String,
        modelContext: ModelContext
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        guard let userEmail = authService.currentUser?.email else {
            Logger.error("❌ Cannot sync: user email not available")
            throw NSError(domain: "ProjectSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "User email not available"])
        }
        
        Logger.debug("🔄 Syncing projects from cloud for user: \(userId)")
        Logger.debug("🆔 User ID being used for sync: '\(userId)'")
        Logger.debug("📧 User email: '\(userEmail)'")
        
        do {
            // Get projects owned by this user
            Logger.debug("🔍 Fetching owned projects...")
            let ownedProjects = try await firestoreService.getUserProjects(userId: userId)
            Logger.debug("📦 Found \(ownedProjects.count) owned projects")
            for (projectId, projectData) in ownedProjects {
                Logger.debug("   - \(projectData["name"] ?? "Unknown") (\(projectId))")
            }
            
            // Get projects where user is a reviewer (with email fallback and backfill)
            Logger.debug("🔍 Fetching reviewer projects...")
            let reviewerProjects = try await firestoreService.getProjectsWhereUserIsReviewer(userId: userId, userEmail: userEmail)
            Logger.debug("📦 Found \(reviewerProjects.count) projects where user is a reviewer")
            for (projectId, projectData) in reviewerProjects {
                Logger.debug("   - \(projectData["name"] ?? "Unknown") (\(projectId))")
            }
            
            // Combine and deduplicate projects
            var projectsMap: [String: [String: Any]] = [:]
            for (projectId, projectData) in ownedProjects {
                projectsMap[projectId] = projectData
            }
            for (projectId, projectData) in reviewerProjects {
                projectsMap[projectId] = projectData
            }
            
            let cloudProjects = Array(projectsMap)
            Logger.debug("📦 Total unique projects to sync: \(cloudProjects.count)")
            
            // Track successfully synced project IDs for cleanup later
            var syncedProjectIds = Set<String>()
            
            for (projectId, projectData) in cloudProjects {
                // Check if project already exists locally
                let descriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.firestoreId == projectId }
                )
                let existingProjects = try modelContext.fetch(descriptor)
                
                if existingProjects.isEmpty {
                    // Create new local project
                    Logger.debug("✨ Creating new local project: \(projectData["name"] ?? "Unknown")")
                    
                    let project = Project(
                        name: projectData["name"] as? String ?? "Untitled",
                        clientName: projectData["clientName"] as? String,
                        ownerUserID: projectData["ownerUserId"] as? String ?? userId,
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
                    
                    // Sync reviewers for this project
                    try await syncProjectReviewers(
                        projectId: projectId,
                        project: project,
                        modelContext: modelContext
                    )
                    
                    // Now sync songs for this project
                    try await syncProjectSongsFromCloud(
                        projectId: projectId,
                        project: project,
                        modelContext: modelContext
                    )
                    
                    // Mark as successfully synced
                    syncedProjectIds.insert(projectId)
                } else {
                    Logger.debug("✓ Project already exists locally: \(projectData["name"] ?? "Unknown")")
                    
                    // Still sync reviewers and songs in case there are new ones
                    if let existingProject = existingProjects.first {
                        try await syncProjectReviewers(
                            projectId: projectId,
                            project: existingProject,
                            modelContext: modelContext
                        )
                        
                        try await syncProjectSongsFromCloud(
                            projectId: projectId,
                            project: existingProject,
                            modelContext: modelContext
                        )
                        
                        // Mark as successfully synced
                        syncedProjectIds.insert(projectId)
                    }
                }
            }
            
            // Clean up: Remove any locally cached archived projects that user is only a reviewer for
            // (Approvers should not see archived projects)
            Logger.debug("🧹 Starting cleanup: checking for archived projects to remove...")
            let allLocalProjects = try modelContext.fetch(FetchDescriptor<Project>())
            Logger.debug("🧹 Found \(allLocalProjects.count) local projects to check")
            
            var removedCount = 0
            for localProject in allLocalProjects {
                Logger.debug("🔍 Checking project: \(localProject.name)")
                Logger.debug("   - Status: \(localProject.status.rawValue)")
                Logger.debug("   - isArchived flag: \(localProject.isArchived)")
                Logger.debug("   - Owner: \(localProject.ownerUserID)")
                Logger.debug("   - Current user: \(userId)")
                
                // Check if user is not the owner (i.e., they're only a reviewer)
                if localProject.ownerUserID != userId {
                    Logger.debug("   ℹ️ User is a reviewer (not owner)")
                    
                    // For reviewers: check if project is archived (using either field)
                    // The status might not be updated if Firestore blocked the sync,
                    // so we also check the isArchived boolean
                    if localProject.status == .archived || localProject.isArchived {
                        Logger.debug("   🗑️ REMOVING archived project from reviewer's device: \(localProject.name)")
                        modelContext.delete(localProject)
                        removedCount += 1
                    } else {
                        Logger.debug("   ✓ Project is active - keeping")
                    }
                } else {
                    Logger.debug("   ✓ User is owner - keeping project regardless of archive status")
                }
            }
            
            if removedCount > 0 {
                try modelContext.save()
                Logger.debug("🧹 Cleanup complete: removed \(removedCount) archived project(s)")
            } else {
                Logger.debug("🧹 Cleanup complete: no archived projects to remove")
            }
            
            // Additional cleanup: Remove projects and their songs that failed to sync
            // When a project is archived, Firestore blocks access for reviewers.
            // Any locally cached project that wasn't successfully synced should be removed.
            Logger.debug("🧹 Checking for inaccessible projects (e.g., archived by producer)...")
            
            var inaccessibleProjectsRemoved = 0
            for localProject in allLocalProjects {
                // Skip if already removed in previous cleanup
                if localProject.isDeleted { continue }
                
                // Check if this project was successfully synced from Firestore
                // Don't trust the local owner field - it may be corrupted
                if let firestoreId = localProject.firestoreId {
                    let wasSuccessfullySynced = syncedProjectIds.contains(firestoreId)
                    
                    if !wasSuccessfullySynced {
                        Logger.debug("🔍 Project '\(localProject.name)' (ID: \(firestoreId))")
                        Logger.debug("   - Was NOT in synced list (likely archived/inaccessible)")
                        Logger.debug("   - Local owner: \(localProject.ownerUserID)")
                        Logger.debug("   - Current user: \(userId)")
                        
                        // Only remove if user is not the actual owner
                        // Check by seeing if this was an owned project
                        // If user owns it, it would have been synced
                        if localProject.ownerUserID != userId {
                            Logger.debug("   - Local data shows user as reviewer")
                            Logger.debug("   - 🗑️ REMOVING project and all its songs from reviewer's device")
                            modelContext.delete(localProject)
                            inaccessibleProjectsRemoved += 1
                        } else {
                            // Local data says user owns it, but it wasn't synced
                            // This indicates corrupted data - the project is likely archived and user is actually a reviewer
                            Logger.warning("   - ⚠️ Local data says user owns project, but it wasn't synced (corrupted data)")
                            Logger.debug("   - 🗑️ REMOVING project with corrupted owner data")
                            modelContext.delete(localProject)
                            inaccessibleProjectsRemoved += 1
                        }
                    }
                }
            }
            
            if inaccessibleProjectsRemoved > 0 {
                try modelContext.save()
                Logger.debug("🧹 Inaccessible projects cleanup complete: removed \(inaccessibleProjectsRemoved) project(s) and their songs")
            } else {
                Logger.debug("🧹 Inaccessible projects cleanup complete: all reviewer projects are accessible")
            }
            
            // Final cleanup: Remove orphaned songs whose parent project no longer exists
            // or whose project failed to sync from Firestore
            Logger.debug("🧹 Checking for orphaned songs without valid parent project...")
            let allLocalSongs = try modelContext.fetch(FetchDescriptor<Song>())
            Logger.debug("🧹 Found \(allLocalSongs.count) local songs to check")
            
            var orphanedSongsRemoved = 0
            for song in allLocalSongs {
                let songProjectId = song.project?.firestoreId
                let songProjectName = song.project?.name
                let songOwner = song.project?.ownerUserID
                
                Logger.debug("🔍 Checking song '\(song.name)'")
                Logger.debug("   - Project ID: \(songProjectId ?? "nil")")
                Logger.debug("   - Project name: \(songProjectName ?? "nil")")
                Logger.debug("   - Project owner: \(songOwner ?? "nil")")
                Logger.debug("   - Song's firestoreId: \(song.firestoreId ?? "nil")")
                
                // Case 1: Song has no parent project at all
                if song.project == nil {
                    Logger.debug("   🗑️ REMOVING orphaned song - no parent project")
                    modelContext.delete(song)
                    orphanedSongsRemoved += 1
                    continue
                }
                
                // Case 2: Song's parent project exists - check if it was successfully synced
                if let projectId = songProjectId {
                    // Check if this project was successfully synced from Firestore
                    let wasProjectSynced = syncedProjectIds.contains(projectId)
                    Logger.debug("   - Project was synced from Firestore: \(wasProjectSynced)")
                    
                    if !wasProjectSynced {
                        // Project wasn't synced - either archived or inaccessible
                        // Delete the song regardless of what the local owner field says
                        // (the local owner field may be corrupted)
                        Logger.debug("   🗑️ REMOVING orphaned song - parent project not synced from Firestore")
                        modelContext.delete(song)
                        orphanedSongsRemoved += 1
                    } else {
                        Logger.debug("   ✓ Song's project was successfully synced - keeping")
                    }
                }
            }
            
            if orphanedSongsRemoved > 0 {
                try modelContext.save()
                Logger.debug("🧹 Orphaned songs cleanup complete: removed \(orphanedSongsRemoved) song(s)")
            } else {
                Logger.debug("🧹 Orphaned songs cleanup complete: no orphaned songs found")
            }
            
            Logger.debug("✅ Finished syncing all projects")
            
        } catch {
            Logger.error("❌ Error syncing projects: \(error)")
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
        Logger.debug("🎵 Found \(cloudSongs.count) songs for project")
        
        for (songId, songData) in cloudSongs {
            // Check if song already exists locally
            let descriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.firestoreId == songId }
            )
            let existingSongs = try modelContext.fetch(descriptor)
            
            if existingSongs.isEmpty {
                Logger.debug("✨ Creating new local song: \(songData["name"] ?? "Unknown")")
                
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
                Logger.debug("✓ Song already exists locally: \(songData["name"] ?? "Unknown")")
                
                // Update existing song's fields from Firestore
                if let existingSong = existingSongs.first {
                    var needsSave = false
                    
                    // Update name if different
                    if let cloudName = songData["name"] as? String, existingSong.name != cloudName {
                        Logger.debug("   🔄 Updating song name: '\(existingSong.name)' → '\(cloudName)'")
                        existingSong.name = cloudName
                        needsSave = true
                    }
                    
                    // Update artist if different
                    if let cloudArtist = songData["artist"] as? String, existingSong.artist != cloudArtist {
                        existingSong.artist = cloudArtist
                        needsSave = true
                    }
                    
                    // Update notes if different
                    if let cloudNotes = songData["notes"] as? String, existingSong.notes != cloudNotes {
                        existingSong.notes = cloudNotes
                        needsSave = true
                    }
                    
                    // Update sort order if different
                    if let cloudSortOrder = songData["sortOrder"] as? Int, existingSong.sortOrder != cloudSortOrder {
                        existingSong.sortOrder = cloudSortOrder
                        needsSave = true
                    }
                    
                    // Update status if different
                    if let statusString = songData["status"] as? String,
                       let cloudStatus = SongStatus(rawValue: statusString),
                       existingSong.status != cloudStatus {
                        existingSong.status = cloudStatus
                        needsSave = true
                    }
                    
                    if needsSave {
                        try modelContext.save()
                        Logger.debug("   ✅ Song fields updated from Firestore")
                    }
                    
                    // Still sync mixes in case there are new ones or updates
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
        Logger.debug("🎚️ Found \(cloudMixes.count) mixes for song")
        
        for (mixId, mixData) in cloudMixes {
            // Check if mix already exists locally
            let descriptor = FetchDescriptor<Mix>(
                predicate: #Predicate { $0.firestoreId == mixId }
            )
            let existingMixes = try modelContext.fetch(descriptor)
            
            if existingMixes.isEmpty {
                Logger.debug("✨ Creating new local mix: \(mixData["name"] ?? "Unknown")")
                
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
                
                Logger.debug("📥 Mix metadata synced (audio will download on demand)")
                
                // Sync approvals for this mix
                await syncMixApprovalsFromCloud(
                    projectId: projectId,
                    songId: songId,
                    mixId: mixId,
                    mix: mix,
                    project: song.project!,
                    modelContext: modelContext
                )
            } else {
                Logger.debug("✓ Mix already exists locally: \(mixData["name"] ?? "Unknown")")
                
                // Timestamp-based conflict resolution
                if let existingMix = existingMixes.first {
                    // Check if cloud version is deleted
                    let isDeletedInCloud = mixData["isDeleted"] as? Bool ?? false
                    
                    if isDeletedInCloud && !existingMix.isDeleted {
                        Logger.debug("🗑️ Mix deleted in cloud - marking local copy as deleted")
                        existingMix.isDeleted = true
                        existingMix.lastModifiedAt = Date()
                        try modelContext.save()
                        continue
                    }
                    
                    // Get cloud updated timestamp
                    var cloudUpdatedAt: Date?
                    if let timestamp = mixData["updatedAt"] as? Timestamp {
                        cloudUpdatedAt = timestamp.dateValue()
                    } else if let timestamp = mixData["uploadedAt"] as? Timestamp {
                        // Fallback to uploadedAt for older mixes
                        cloudUpdatedAt = timestamp.dateValue()
                    }
                    
                    // Compare timestamps for conflict resolution
                    if let cloudDate = cloudUpdatedAt {
                        let localDate = existingMix.lastModifiedAt
                        
                        Logger.debug("   Local lastModifiedAt: \(localDate)")
                        Logger.debug("   Cloud updatedAt: \(cloudDate)")
                        
                        // If local is newer and needs upload, skip cloud update
                        if existingMix.needsUpload && localDate > cloudDate {
                            Logger.debug("   ℹ️ Local version is newer and needs upload - keeping local changes")
                            continue
                        }
                        
                        // If cloud is newer or same, update from cloud
                        if cloudDate >= localDate {
                            Logger.debug("   🔄 Cloud version is newer or equal - updating from cloud")
                            
                            // Update mix properties from cloud
                            if let name = mixData["name"] as? String {
                                existingMix.name = name
                            }
                            
                            if let statusString = mixData["approvalStatus"] as? String,
                               let status = MixStatus(rawValue: statusString) {
                                if existingMix.approvalStatus != status {
                                    Logger.debug("   🔄 Updating approval status: \(existingMix.approvalStatus.rawValue) → \(status.rawValue)")
                                    existingMix.approvalStatus = status
                                }
                            }
                            
                            if let notes = mixData["notes"] as? String, !notes.isEmpty {
                                existingMix.notes = notes
                            }
                            
                            // Update sync metadata
                            existingMix.lastModifiedAt = cloudDate
                            existingMix.needsUpload = false
                            
                            try modelContext.save()
                            Logger.debug("   ✅ Mix updated from cloud")
                        }
                    } else {
                        // No timestamp in cloud - just update approval status as before
                        Logger.warning("   ⚠️ No timestamp in cloud data - updating approval status only")
                        
                        if let statusString = mixData["approvalStatus"] as? String,
                           let status = MixStatus(rawValue: statusString),
                           existingMix.approvalStatus != status {
                            Logger.debug("   🔄 Updating approval status: \(existingMix.approvalStatus.rawValue) → \(status.rawValue)")
                            existingMix.approvalStatus = status
                            try modelContext.save()
                        }
                    }
                    
                    // Sync approvals for existing mix
                    await syncMixApprovalsFromCloud(
                        projectId: projectId,
                        songId: songId,
                        mixId: mixId,
                        mix: existingMix,
                        project: song.project!,
                        modelContext: modelContext
                    )
                }
            }
        }
    }
    
    // MARK: - Reviewer Management
    
    func addReviewer(
        projectId: String,
        reviewer: Reviewer
    ) async throws {
        try await firestoreService.addReviewer(projectId: projectId, reviewer: reviewer)
    }
    
    func removeReviewer(
        projectId: String,
        reviewerId: String
    ) async throws {
        try await firestoreService.removeReviewer(projectId: projectId, reviewerId: reviewerId)
    }
    
    func updateReviewerKeyApproverStatus(
        projectId: String,
        reviewerId: String,
        isKeyApprover: Bool
    ) async throws {
        try await firestoreService.updateReviewerKeyApproverStatus(
            projectId: projectId,
            reviewerId: reviewerId,
            isKeyApprover: isKeyApprover
        )
    }
    
    func updateReviewer(
        projectId: String,
        reviewer: Reviewer
    ) async throws {
        try await firestoreService.updateReviewer(
            projectId: projectId,
            reviewer: reviewer
        )
    }
    
    // MARK: - Listen to Reviewers
    
    func startListeningToReviewers(
        projectId: String,
        project: Project,
        modelContext: ModelContext
    ) -> FirebaseFirestore.ListenerRegistration {
        Logger.debug("👂 Setting up reviewer listener for project: \(projectId)")
        return firestoreService.listenToReviewers(projectId: projectId) { [weak self] documents in
            guard let self = self else { return }
            
            Logger.debug("📬 Received \(documents.count) reviewer documents from Firestore")
            
            Task { @MainActor in
                // Get all reviewer IDs from Firestore
                let firestoreReviewerIds = Set(documents.compactMap { UUID(uuidString: $0.documentID) })
                
                // Get all local reviewers for this project
                let localReviewers = project.reviewers
                
                // Remove local reviewers that no longer exist in Firestore
                for localReviewer in localReviewers {
                    if !firestoreReviewerIds.contains(localReviewer.id) {
                        Logger.debug("🗑️ Removing deleted reviewer: \(localReviewer.displayName)")
                        modelContext.delete(localReviewer)
                    }
                }
                
                // Add or update reviewers from Firestore
                for document in documents {
                    await self.processReviewerFromCloud(
                        document: document,
                        project: project,
                        modelContext: modelContext
                    )
                }
                
                // Save all changes
                do {
                    try modelContext.save()
                    Logger.debug("✅ Reviewer sync completed")
                } catch {
                    Logger.error("❌ Error saving reviewer changes: \(error)")
                }
            }
        }
    }
    
    private func processReviewerFromCloud(
        document: FirebaseFirestore.QueryDocumentSnapshot,
        project: Project,
        modelContext: ModelContext
    ) async {
        let data = document.data()
        let reviewerId = document.documentID
        
        guard let reviewerUUID = UUID(uuidString: reviewerId) else {
            // Skip userId-based documents (used for Firebase security rules)
            // These are intentionally created with userId as document ID for rule matching
            return
        }
        
        Logger.debug("📥 Processing reviewer from cloud: \(reviewerId)")
        
        // Check if reviewer already exists locally
        let descriptor = FetchDescriptor<Reviewer>(
            predicate: #Predicate { reviewer in
                reviewer.id == reviewerUUID
            }
        )
        
        do {
            let existingReviewers = try modelContext.fetch(descriptor)
            
            // Parse common data first (needed for both new and existing reviewers)
            guard let displayName = data["displayName"] as? String,
                  let email = data["email"] as? String,
                  let roleString = data["role"] as? String,
                  let role = ReviewerRole(rawValue: roleString) else {
                Logger.warning("⚠️ Invalid reviewer data for \(reviewerId)")
                return
            }
            
            // Handle inviteStatus with default fallback for legacy data
            let status: ReviewerInviteStatus
            var needsFirestoreUpdate = false
            if let statusString = data["inviteStatus"] as? String,
               let parsedStatus = ReviewerInviteStatus(rawValue: statusString) {
                status = parsedStatus
            } else {
                // Default to .accepted for reviewers without inviteStatus (legacy data)
                Logger.warning("⚠️ Missing inviteStatus for reviewer \(reviewerId), defaulting to .accepted")
                status = .accepted
                needsFirestoreUpdate = true
            }
            
            let isKeyApprover = data["isKeyApprover"] as? Bool ?? false
            
            if existingReviewers.isEmpty {
                // Create new local reviewer
                
                let reviewer = Reviewer(
                    id: reviewerUUID,
                    displayName: displayName,
                    email: email,
                    userId: data["userId"] as? String,
                    role: role,
                    inviteStatus: status,
                    isKeyApprover: isKeyApprover
                )
                
                if let acceptedTimestamp = data["acceptedAt"] as? Timestamp {
                    reviewer.acceptedAt = acceptedTimestamp.dateValue()
                }
                
                reviewer.project = project
                modelContext.insert(reviewer)
                try modelContext.save()
                
                Logger.debug("✨ Created new reviewer from cloud: \(displayName)")
                
                // Fix missing inviteStatus in Firestore
                if needsFirestoreUpdate {
                    Task {
                        do {
                            try await self.firestoreService.updateReviewerField(
                                projectId: project.firestoreId ?? "",
                                reviewerId: reviewerId,
                                field: "inviteStatus",
                                value: status.rawValue
                            )
                            Logger.debug("✅ Fixed missing inviteStatus in Firestore for \(displayName)")
                        } catch {
                            Logger.warning("⚠️ Failed to update inviteStatus in Firestore: \(error)")
                        }
                    }
                }
            } else {
                Logger.debug("✓ Reviewer already exists locally: \(data["displayName"] ?? "Unknown")")
                
                // Update existing reviewer with latest data from Firestore
                if let existingReviewer = existingReviewers.first(where: { $0.id.uuidString == reviewerId }) {
                    Logger.debug("   Updating existing reviewer with cloud data...")
                    
                    // Update fields that may have changed
                    existingReviewer.displayName = displayName
                    existingReviewer.email = email
                    existingReviewer.role = role
                    existingReviewer.inviteStatus = status
                    existingReviewer.isKeyApprover = isKeyApprover
                    
                    // Update userId if it was linked
                    if let userId = data["userId"] as? String, !userId.isEmpty {
                        existingReviewer.userId = userId
                    }
                    
                    // Update acceptedAt if present
                    if let acceptedAtTimestamp = data["acceptedAt"] as? Timestamp {
                        existingReviewer.acceptedAt = acceptedAtTimestamp.dateValue()
                    }
                    
                    // Update invitedAt if present
                    if let invitedAtTimestamp = data["invitedAt"] as? Timestamp {
                        existingReviewer.invitedAt = invitedAtTimestamp.dateValue()
                    }
                    
                    Logger.debug("   ✅ Updated reviewer: \(displayName) with status: \(status.rawValue)")
                }
            }
        } catch {
            Logger.error("❌ Error processing reviewer: \(error)")
        }
    }
    
    // MARK: - Approval Real-time Sync
    
    func startListeningToApprovals(
        projectId: String,
        songId: String,
        mixId: String,
        mix: Mix,
        project: Project,
        modelContext: ModelContext
    ) -> FirebaseFirestore.ListenerRegistration {
        Logger.debug("👂 Setting up approval listener for mix: \(mixId)")
        return firestoreService.setupApprovalsListener(
            projectId: projectId,
            songId: songId,
            mixId: mixId
        ) { [weak self] approvalDocs in
            guard let self = self else { return }
            
            Logger.debug("📬 Received \(approvalDocs.count) approval documents from Firestore")
            
            Task { @MainActor in
                for approvalData in approvalDocs {
                    await self.processApprovalFromCloud(
                        approvalData: approvalData,
                        mix: mix,
                        project: project,
                        modelContext: modelContext
                    )
                }
            }
        }
    }
    
    private func processApprovalFromCloud(
        approvalData: [String: Any],
        mix: Mix,
        project: Project,
        modelContext: ModelContext
    ) async {
        guard let reviewerUserId = approvalData["reviewerUserId"] as? String,
              let statusString = approvalData["status"] as? String,
              let status = ApprovalStatus(rawValue: statusString) else {
            Logger.warning("⚠️ Invalid approval data")
            return
        }
        
        Logger.debug("📥 Processing approval from cloud for user: \(reviewerUserId)")
        
        // Find the reviewer by userId
        var reviewer = project.reviewers.first(where: { $0.userId == reviewerUserId })
        
        // If not found by userId, try to find by matching the userId from Firestore reviewer doc
        if reviewer == nil {
            Logger.warning("⚠️ Reviewer not found by userId, checking Firestore for match...")
            
            // Try to find the reviewer in Firestore by userId and link it
            if let projectId = project.firestoreId {
                do {
                    let cloudReviewers = try await firestoreService.getProjectReviewers(projectId: projectId)
                    
                    // Find the cloud reviewer document that has this userId
                    for (reviewerId, reviewerData) in cloudReviewers {
                        if let cloudUserId = reviewerData["userId"] as? String,
                           cloudUserId == reviewerUserId {
                            // Found the matching reviewer - try to find locally by reviewerId
                            if let reviewerUUID = UUID(uuidString: reviewerId),
                               let localReviewer = project.reviewers.first(where: { $0.id == reviewerUUID }) {
                                Logger.debug("✅ Found reviewer by document ID, updating userId: \(localReviewer.displayName)")
                                localReviewer.userId = reviewerUserId
                                try? modelContext.save()
                                reviewer = localReviewer
                                break
                            }
                        }
                    }
                } catch {
                    Logger.error("❌ Error fetching reviewers: \(error)")
                }
            }
        }
        
        guard let reviewer = reviewer else {
            Logger.warning("⚠️ Reviewer not found for userId: \(reviewerUserId) - cannot sync approval")
            return
        }
        
        // Check if approval already exists for this reviewer and mix
        let existingApproval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id })
        
        if let approval = existingApproval {
            // Update existing approval
            let oldStatus = approval.status
            approval.status = status
            if let updatedTimestamp = approvalData["updatedAt"] as? Timestamp {
                approval.updatedAt = updatedTimestamp.dateValue()
            }
            Logger.debug("✅ Updated existing approval for \(reviewer.displayName)")
            
            // Show in-app notification if status changed and user is producer
            if oldStatus != status, authService.currentUser?.isProducer == true {
                showApprovalNotification(
                    reviewerName: reviewer.displayName,
                    status: status,
                    mixName: mix.name,
                    songName: mix.song?.name ?? "Song",
                    projectName: project.name
                )
            }
        } else {
            // Create new approval
            let newApproval = Approval(status: status)
            newApproval.mix = mix
            newApproval.reviewer = reviewer
            
            if let createdTimestamp = approvalData["createdAt"] as? Timestamp {
                newApproval.createdAt = createdTimestamp.dateValue()
            }
            if let updatedTimestamp = approvalData["updatedAt"] as? Timestamp {
                newApproval.updatedAt = updatedTimestamp.dateValue()
            }
            
            modelContext.insert(newApproval)
            Logger.debug("✅ Created new approval for \(reviewer.displayName)")
            
            // Show in-app notification for new approval if user is producer
            if authService.currentUser?.isProducer == true {
                showApprovalNotification(
                    reviewerName: reviewer.displayName,
                    status: status,
                    mixName: mix.name,
                    songName: mix.song?.name ?? "Song",
                    projectName: project.name
                )
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            Logger.error("❌ Error saving approval: \(error)")
        }
    }
    
    private func syncMixApprovalsFromCloud(
        projectId: String,
        songId: String,
        mixId: String,
        mix: Mix,
        project: Project,
        modelContext: ModelContext
    ) async {
        do {
            let approvals = try await firestoreService.getApprovals(
                projectId: projectId,
                songId: songId,
                mixId: mixId
            )
            
            Logger.debug("📥 Syncing \(approvals.count) approvals for mix")
            
            for (_, approvalData) in approvals {
                await processApprovalFromCloud(
                    approvalData: approvalData,
                    mix: mix,
                    project: project,
                    modelContext: modelContext
                )
            }
        } catch {
            Logger.error("❌ Error syncing approvals: \(error)")
        }
    }
    
    private func syncProjectReviewers(
        projectId: String,
        project: Project,
        modelContext: ModelContext
    ) async throws {
        let cloudReviewers = try await firestoreService.getProjectReviewers(projectId: projectId)
        Logger.debug("👥 Found \(cloudReviewers.count) reviewers for project")
        
        for (reviewerId, reviewerData) in cloudReviewers {
            // Convert reviewerId string to UUID
            guard let reviewerUUID = UUID(uuidString: reviewerId) else {
                // Skip userId-based documents (used for Firebase security rules)
                // These are intentionally created with userId as document ID for rule matching
                continue
            }
            
            // Parse common data first (needed for both new and existing reviewers)
            guard let displayName = reviewerData["displayName"] as? String,
                  let email = reviewerData["email"] as? String,
                  let roleString = reviewerData["role"] as? String,
                  let role = ReviewerRole(rawValue: roleString) else {
                Logger.warning("⚠️ Invalid reviewer data for \(reviewerId)")
                continue
            }
            
            // Handle inviteStatus with default fallback for legacy data
            let status: ReviewerInviteStatus
            var needsFirestoreUpdate = false
            if let statusString = reviewerData["inviteStatus"] as? String,
               let parsedStatus = ReviewerInviteStatus(rawValue: statusString) {
                status = parsedStatus
            } else {
                // Default to .accepted for reviewers without inviteStatus (legacy data)
                Logger.warning("⚠️ Missing inviteStatus for reviewer \(reviewerId), defaulting to .accepted")
                status = .accepted
                needsFirestoreUpdate = true
            }
            
            let isKeyApprover = reviewerData["isKeyApprover"] as? Bool ?? false
            
            // Check if reviewer already exists locally
            let descriptor = FetchDescriptor<Reviewer>(
                predicate: #Predicate { $0.id == reviewerUUID }
            )
            let existingReviewers = try modelContext.fetch(descriptor)
            
            if existingReviewers.isEmpty {
                Logger.debug("✨ Creating new local reviewer: \(displayName)")
                
                let reviewer = Reviewer(
                    id: reviewerUUID,
                    displayName: displayName,
                    email: email,
                    userId: reviewerData["userId"] as? String,
                    role: role,
                    inviteStatus: status,
                    isKeyApprover: isKeyApprover
                )
                
                if let acceptedTimestamp = reviewerData["acceptedAt"] as? Timestamp {
                    reviewer.acceptedAt = acceptedTimestamp.dateValue()
                }
                
                reviewer.project = project
                modelContext.insert(reviewer)
                try modelContext.save()
                
                Logger.debug("📥 Reviewer synced: \(displayName)")
                
                // Fix missing inviteStatus in Firestore
                if needsFirestoreUpdate {
                    Task {
                        do {
                            try await self.firestoreService.updateReviewerField(
                                projectId: projectId,
                                reviewerId: reviewerId,
                                field: "inviteStatus",
                                value: status.rawValue
                            )
                            Logger.debug("✅ Fixed missing inviteStatus in Firestore for \(displayName)")
                        } catch {
                            Logger.warning("⚠️ Failed to update inviteStatus in Firestore: \(error)")
                        }
                    }
                }
            } else {
                Logger.debug("✓ Reviewer already exists locally: \(reviewerData["displayName"] ?? "Unknown")")
                
                // Update existing reviewer with latest data from Firestore
                if let existingReviewer = existingReviewers.first(where: { $0.id.uuidString == reviewerId }) {
                    Logger.debug("   Updating existing reviewer with cloud data...")
                    
                    // Update fields that may have changed
                    existingReviewer.displayName = displayName
                    existingReviewer.email = email
                    existingReviewer.role = role
                    existingReviewer.inviteStatus = status
                    existingReviewer.isKeyApprover = isKeyApprover
                    
                    // Update userId if it was linked
                    if let userId = reviewerData["userId"] as? String, !userId.isEmpty {
                        existingReviewer.userId = userId
                    }
                    
                    // Update acceptedAt if present
                    if let acceptedAtTimestamp = reviewerData["acceptedAt"] as? Timestamp {
                        existingReviewer.acceptedAt = acceptedAtTimestamp.dateValue()
                    }
                    
                    // Update invitedAt if present
                    if let invitedAtTimestamp = reviewerData["invitedAt"] as? Timestamp {
                        existingReviewer.invitedAt = invitedAtTimestamp.dateValue()
                    }
                    
                    Logger.debug("   ✅ Updated reviewer: \(displayName) with status: \(status.rawValue)")
                }
            }
        }
    }
    
    // MARK: - Organization Sync
    
    func syncUserOrganization(
        userId: String,
        modelContext: ModelContext
    ) async throws {
        Logger.debug("🏢 Starting organization sync for user: \(userId)")
        
        // Fetch organization from Firestore
        guard let (firestoreId, data) = try await firestoreService.getUserOrganization(userId: userId) else {
            Logger.debug("ℹ️ No organization found in Firestore for user")
            return
        }
        
        Logger.debug("☁️ Found organization in Firestore: \(firestoreId)")
        
        // Check if organization already exists locally
        Logger.debug("🔍 Checking for existing local organization...")
        
        // First try to fetch all organizations and filter manually to avoid predicate issues
        let allOrgsDescriptor = FetchDescriptor<Organization>()
        let allOrganizations = try modelContext.fetch(allOrgsDescriptor)
        
        Logger.debug("📊 Found \(allOrganizations.count) total local organizations")
        
        // Check by firestoreId or memberIds
        let existingOrganizations = allOrganizations.filter { org in
            if let orgFirestoreId = org.firestoreId, orgFirestoreId == firestoreId {
                Logger.debug("✓ Match by firestoreId: \(orgFirestoreId)")
                return true
            }
            if org.memberIds.contains(userId) {
                Logger.debug("✓ Match by memberIds")
                return true
            }
            return false
        }
        
        if let existingOrg = existingOrganizations.first {
            // Update existing organization
            Logger.debug("📝 Updating existing organization: \(existingOrg.name)")
            
            if let name = data["name"] as? String {
                existingOrg.name = name
            }
            if let typeString = data["type"] as? String,
               let type = OrganizationType(rawValue: typeString) {
                existingOrg.type = type
            }
            if let maxProducers = data["maxProducers"] as? Int {
                existingOrg.maxProducers = maxProducers
            }
            if let isActive = data["isActive"] as? Bool {
                existingOrg.isActive = isActive
            }
            if let memberIds = data["memberIds"] as? [String] {
                existingOrg.memberIds = memberIds
            }
            
            // Update optional fields
            existingOrg.address = data["address"] as? String
            existingOrg.city = data["city"] as? String
            existingOrg.state = data["state"] as? String
            existingOrg.zipCode = data["zipCode"] as? String
            existingOrg.country = data["country"] as? String
            existingOrg.phone = data["phone"] as? String
            existingOrg.email = data["email"] as? String
            existingOrg.website = data["website"] as? String
            existingOrg.taxId = data["taxId"] as? String
            existingOrg.notes = data["notes"] as? String
            existingOrg.licenseType = data["licenseType"] as? String
            
            if let licenseStartTimestamp = data["licenseStartDate"] as? Timestamp {
                existingOrg.licenseStartDate = licenseStartTimestamp.dateValue()
            }
            if let licenseExpiryTimestamp = data["licenseExpiryDate"] as? Timestamp {
                existingOrg.licenseExpiryDate = licenseExpiryTimestamp.dateValue()
            }
            if let updatedTimestamp = data["updatedAt"] as? Timestamp {
                existingOrg.updatedAt = updatedTimestamp.dateValue()
            }
            
            existingOrg.firestoreId = firestoreId
            
            try modelContext.save()
            Logger.debug("✅ Organization updated from Firestore")
        } else {
            // Create new organization
            Logger.debug("✨ Creating new organization from Firestore")
            
            guard let name = data["name"] as? String,
                  let typeString = data["type"] as? String,
                  let type = OrganizationType(rawValue: typeString) else {
                Logger.warning("⚠️ Missing required organization data")
                return
            }
            
            let organization = Organization(
                name: name,
                type: type,
                address: data["address"] as? String,
                city: data["city"] as? String,
                state: data["state"] as? String,
                zipCode: data["zipCode"] as? String,
                country: data["country"] as? String,
                phone: data["phone"] as? String,
                email: data["email"] as? String,
                website: data["website"] as? String,
                licenseType: data["licenseType"] as? String,
                maxProducers: data["maxProducers"] as? Int ?? 1
            )
            
            // Set the ID to match Firestore
            organization.id = UUID(uuidString: firestoreId) ?? UUID()
            organization.firestoreId = firestoreId
            
            // Set member IDs
            if let memberIds = data["memberIds"] as? [String] {
                organization.memberIds = memberIds
            }
            
            // Set other optional fields
            organization.taxId = data["taxId"] as? String
            organization.notes = data["notes"] as? String
            organization.isActive = data["isActive"] as? Bool ?? true
            
            if let licenseStartTimestamp = data["licenseStartDate"] as? Timestamp {
                organization.licenseStartDate = licenseStartTimestamp.dateValue()
            }
            if let licenseExpiryTimestamp = data["licenseExpiryDate"] as? Timestamp {
                organization.licenseExpiryDate = licenseExpiryTimestamp.dateValue()
            }
            if let createdTimestamp = data["createdAt"] as? Timestamp {
                organization.createdAt = createdTimestamp.dateValue()
            }
            if let updatedTimestamp = data["updatedAt"] as? Timestamp {
                organization.updatedAt = updatedTimestamp.dateValue()
            }
            
            modelContext.insert(organization)
            try modelContext.save()
            Logger.debug("✅ Organization created from Firestore: \(organization.name)")
        }
    }
    
    // MARK: - Auto-Accept Pending Invitations
    
    func acceptPendingInvitations(
        userId: String,
        userEmail: String,
        modelContext: ModelContext
    ) async throws {
        Logger.debug("📬 Checking for pending invitations for: \(userEmail)")
        
        var invitationsAccepted = 0
        
        do {
            // Use collection group query to find all reviewers with this email across all projects
            let pendingInvitations = try await firestoreService.findPendingInvitationsByEmail(email: userEmail)
            Logger.debug("🔍 Found \(pendingInvitations.count) reviewer record(s) with email: \(userEmail)")
            
            for invitation in pendingInvitations {
                // Check if userId-based document exists (for security rules)
                let userIdReviewerRef = Firestore.firestore()
                    .collection("projects")
                    .document(invitation.projectId)
                    .collection("reviewers")
                    .document(userId)

                let userIdDocSnapshot = try await userIdReviewerRef.getDocument()
                let userIdDocExists = userIdDocSnapshot.exists

                // Check if UUID-based document has userId linked
                let userIdValue = invitation.data["userId"]
                let hasNoUserId = userIdValue == nil ||
                                 userIdValue is NSNull ||
                                 (userIdValue as? String)?.isEmpty == true

                if hasNoUserId || !userIdDocExists {
                    Logger.debug("✉️ Found pending invitation in project: \(invitation.projectId)")
                    Logger.debug("   Reviewer email: \(invitation.data["email"] ?? ""), Document ID: \(invitation.reviewerId)")
                    Logger.debug("   hasNoUserId: \(hasNoUserId), userIdDocExists: \(userIdDocExists)")

                    // Update UUID-based reviewer document with userId and accept status if needed
                    if hasNoUserId {
                        Logger.debug("🔗 Updating UUID-based reviewer document (\(invitation.reviewerId)) with userId: \(userId)")
                        try await firestoreService.updateReviewer(
                            projectId: invitation.projectId,
                            reviewerId: invitation.reviewerId,
                            data: [
                                "userId": userId,
                                "inviteStatus": ReviewerInviteStatus.accepted.rawValue,
                                "acceptedAt": Timestamp(date: Date())
                            ]
                        )
                        Logger.debug("✅ Updated UUID-based reviewer document with userId")
                    }

                    // Create userId-based reviewer document for security rules if it doesn't exist
                    if !userIdDocExists {
                        Logger.debug("🔗 Creating userId-based reviewer document at: projects/\(invitation.projectId)/reviewers/\(userId)")
                        try await userIdReviewerRef.setData([
                            "email": invitation.data["email"] ?? userEmail,
                            "userId": userId,
                            "inviteStatus": ReviewerInviteStatus.accepted.rawValue,
                            "acceptedAt": Timestamp(date: Date())
                        ])
                        Logger.debug("✅ Created userId-based reviewer document")
                    }

                    invitationsAccepted += 1
                    Logger.debug("✅ Accepted invitation and linked userId for project: \(invitation.projectId)")
                    Logger.debug("   - Total invitations accepted so far: \(invitationsAccepted)")
                    
                    // Delete the pending_invitations document now that it's been accepted
                    let pendingInviteRef = Firestore.firestore()
                        .collection("pending_invitations")
                        .document(userEmail.lowercased())
                    try await pendingInviteRef.delete()
                    Logger.debug("✅ Deleted pending_invitations document for: \(userEmail)")
                } else {
                    Logger.debug("✓ Reviewer already fully linked in project: \(invitation.projectId)")
                }
            }
            
            if invitationsAccepted > 0 {
                Logger.debug("🎉 Accepted \(invitationsAccepted) pending invitation(s)")
            } else if pendingInvitations.isEmpty {
                Logger.debug("ℹ️ No reviewer records found for email: \(userEmail)")
            } else {
                Logger.debug("ℹ️ All reviewer records already have userId linked")
            }
        } catch {
            Logger.warning("⚠️ Error checking for pending invitations: \(error)")
            Logger.debug("   Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Auto-Sync Unsyncced Mixes
    
    /// Automatically finds and uploads mixes that haven't been synced to the cloud yet
    /// This runs on app launch and network reconnect to ensure all local changes are backed up
    func syncUnsyncedMixesToCloud(modelContext: ModelContext) async throws {
        guard authService.currentUser?.id != nil else {
            Logger.warning("⚠️ Cannot sync - no authenticated user")
            return
        }
        
        Logger.debug("🔄 Starting auto-sync of unsyncced mixes...")
        
        // Query for mixes that need upload
        let descriptor = FetchDescriptor<Mix>(
            predicate: #Predicate<Mix> { mix in
                mix.needsUpload == true || (mix.isUploaded == false && mix.assetFileName != nil)
            }
        )
        
        let unsyncedMixes = try modelContext.fetch(descriptor)
        
        guard !unsyncedMixes.isEmpty else {
            Logger.debug("✅ No unsyncced mixes found")
            return
        }
        
        Logger.debug("📤 Found \(unsyncedMixes.count) mix(es) that need uploading")
        
        var successCount = 0
        var failCount = 0
        
        for mix in unsyncedMixes {
            // Get the song and project info
            guard let song = mix.song,
                  let project = song.project,
                  let projectId = project.firestoreId,
                  let songId = song.firestoreId else {
                Logger.warning("⚠️ Mix '\(mix.name)' missing required project/song info - skipping")
                continue
            }
            
            // Only project owners can sync mixes to Firestore
            // Approvers have read-only access to mixes
            guard project.ownerUserID == authService.currentUser?.id else {
                Logger.debug("⏭️ Skipping mix '\(mix.name)' - user is not project owner")
                continue
            }
            
            // Handle deleted mixes - propagate deletion to cloud
            if mix.isDeleted {
                Logger.debug("🗑️ Syncing deletion for mix: \(mix.name)")
                
                if let mixId = mix.firestoreId {
                    do {
                        try await firestoreService.deleteMix(
                            projectId: projectId,
                            songId: songId,
                            mixId: mixId
                        )
                        
                        // Mark as synced and actually delete locally
                        await MainActor.run {
                            modelContext.delete(mix)
                            try? modelContext.save()
                        }
                        
                        successCount += 1
                        Logger.debug("✅ Deletion synced and local copy removed: \(mix.name)")
                        
                    } catch {
                        failCount += 1
                        Logger.error("❌ Failed to sync deletion for '\(mix.name)': \(error.localizedDescription)")
                    }
                } else {
                    // Mix was never uploaded, just delete locally
                    Logger.debug("   ℹ️ Mix was never uploaded - removing locally only")
                    await MainActor.run {
                        modelContext.delete(mix)
                        try? modelContext.save()
                    }
                    successCount += 1
                }
                
                continue
            }
            
            // Verify local file exists for non-deleted mixes
            guard mix.resolvedAssetURL != nil else {
                Logger.warning("⚠️ Mix '\(mix.name)' has no local file - skipping")
                continue
            }
            
            do {
                // Check if this is an update to existing cloud mix
                if let mixId = mix.firestoreId, mix.isUploaded {
                    Logger.debug("🔄 Updating existing mix: \(mix.name)")
                    try await firestoreService.updateMix(
                        projectId: projectId,
                        songId: songId,
                        mixId: mixId,
                        mix: mix
                    )
                    
                    await MainActor.run {
                        mix.needsUpload = false
                        try? modelContext.save()
                    }
                    
                    successCount += 1
                    Logger.debug("✅ Successfully updated: \(mix.name)")
                    
                } else {
                    // New mix - upload file and create in Firestore
                    Logger.debug("📤 Uploading new mix: \(mix.name)")
                    try await uploadMix(
                        mix: mix,
                        projectId: projectId,
                        songId: songId,
                        modelContext: modelContext
                    )
                    
                    await MainActor.run {
                        mix.needsUpload = false
                        try? modelContext.save()
                    }
                    
                    successCount += 1
                    Logger.debug("✅ Successfully uploaded: \(mix.name)")
                }
                
            } catch {
                failCount += 1
                Logger.error("❌ Failed to sync '\(mix.name)': \(error.localizedDescription)")
                // Keep needsUpload = true so it retries later
            }
        }
        
        Logger.debug("🎉 Auto-sync complete: \(successCount) uploaded, \(failCount) failed")
    }
    
    // MARK: - Auto-Sync Unsyncced Approvals
    
    /// Automatically finds and uploads approvals that haven't been synced to the cloud yet
    /// This runs on app launch and network reconnect to ensure all local approval changes are backed up
    func syncUnsyncedApprovalsToCloud(modelContext: ModelContext) async throws {
        guard let currentUserId = authService.currentUser?.id else {
            Logger.warning("⚠️ Cannot sync approvals - no authenticated user")
            return
        }
        
        Logger.debug("🔄 Starting auto-sync of unsyncced approvals...")
        
        // Query for approvals that need upload AND belong to the current user
        // Only reviewers can upload their own approvals (per Firestore security rules)
        let descriptor = FetchDescriptor<Approval>(
            predicate: #Predicate<Approval> { approval in
                (approval.needsUpload == true || approval.lastSyncedAt == nil) &&
                approval.reviewer != nil
            }
        )
        
        let unsyncedApprovals = try modelContext.fetch(descriptor)
        
        guard !unsyncedApprovals.isEmpty else {
            Logger.debug("✅ No unsyncced approvals found")
            return
        }
        
        Logger.debug("📤 Found \(unsyncedApprovals.count) approval(s) that need uploading")
        
        var successCount = 0
        var failCount = 0
        
        for approval in unsyncedApprovals {
            // Get the mix, song, and project info
            guard let mix = approval.mix,
                  let song = mix.song,
                  let project = song.project,
                  let projectId = project.firestoreId,
                  let songId = song.firestoreId,
                  let mixId = mix.firestoreId else {
                Logger.warning("⚠️ Approval missing required project/song/mix info - skipping")
                continue
            }
            
            // Get reviewer info
            guard let reviewer = approval.reviewer,
                  let reviewerUserId = reviewer.userId else {
                Logger.warning("⚠️ Approval missing reviewer userId - skipping")
                continue
            }
            
            // Only sync approvals where the current user is the reviewer
            // (Firestore security rules only allow reviewers to update their own approvals)
            guard reviewerUserId == currentUserId else {
                Logger.debug("⏭️ Skipping approval from '\(reviewer.displayName)' - not current user's approval")
                continue
            }
            
            do {
                Logger.debug("📤 Syncing approval for mix '\(mix.name)' by reviewer '\(reviewer.displayName)'")
                
                // Sync to Firestore
                _ = try await firestoreService.createOrUpdateApproval(
                    projectId: projectId,
                    songId: songId,
                    mixId: mixId,
                    approval: approval,
                    reviewerUserId: reviewerUserId
                )
                
                // Mark as synced
                await MainActor.run {
                    approval.needsUpload = false
                    approval.lastSyncedAt = Date()
                    try? modelContext.save()
                }
                
                successCount += 1
                Logger.debug("✅ Successfully synced approval")
                
            } catch {
                failCount += 1
                Logger.error("❌ Failed to sync approval: \(error.localizedDescription)")
                // Keep needsUpload = true so it retries later
            }
        }
        
        Logger.debug("🎉 Approval sync complete: \(successCount) uploaded, \(failCount) failed")
    }
    
    // MARK: - Auto-Sync Unsyncced Songs
    
    /// Automatically finds and uploads songs that haven't been synced to the cloud yet
    /// This runs on app launch and network reconnect to ensure all local song changes are backed up
    func syncUnsyncedSongsToCloud(modelContext: ModelContext) async throws {
        guard authService.currentUser?.id != nil else {
            Logger.warning("⚠️ Cannot sync songs - no authenticated user")
            return
        }
        
        Logger.debug("🔄 Starting auto-sync of unsyncced songs...")
        
        // Query ALL songs to verify they exist in Firestore (temporary debugging)
        // TODO: Revert to optimized query once sync is verified working
        let descriptor = FetchDescriptor<Song>()
        
        let unsyncedSongs = try modelContext.fetch(descriptor)
        
        guard !unsyncedSongs.isEmpty else {
            Logger.debug("✅ No unsyncced songs found")
            return
        }
        
        Logger.debug("📤 Found \(unsyncedSongs.count) song(s) that need uploading")
        
        var successCount = 0
        var failCount = 0
        
        for song in unsyncedSongs {
            // Get the project info first
            guard let project = song.project,
                  let projectId = project.firestoreId else {
                Logger.warning("⚠️ Song '\(song.name)' missing required project info - skipping")
                continue
            }
            
            // Only project owners can sync songs to Firestore
            // Approvers have read-only access to songs
            guard project.ownerUserID == authService.currentUser?.id else {
                Logger.debug("⏭️ Skipping song '\(song.name)' - user is not project owner")
                continue
            }
            
            // If song has a firestoreId, verify it actually exists in Firestore
            // This handles the case where a previous sync attempt set the ID but failed to create the document
            var shouldSync = false
            if let songId = song.firestoreId {
                Logger.debug("🔍 Checking song '\(song.name)' with firestoreId: \(songId)")
                do {
                    // Check if document exists
                    let exists = try await firestoreService.songExists(projectId: projectId, songId: songId)
                    Logger.debug("   - Document exists in Firestore: \(exists)")
                    Logger.debug("   - lastSyncedAt: \(song.lastSyncedAt?.description ?? "nil")")
                    
                    if !exists {
                        Logger.warning("⚠️ Song '\(song.name)' has firestoreId but document doesn't exist - forcing sync")
                        shouldSync = true
                    } else if let lastSync = song.lastSyncedAt,
                              Date().timeIntervalSince(lastSync) < 3600 {
                        let timeSinceSync = Date().timeIntervalSince(lastSync)
                        Logger.debug("⏭️ Skipping recently synced song: \(song.name) (synced \(Int(timeSinceSync))s ago)")
                        continue
                    } else {
                        Logger.debug("✅ Song exists and needs sync (not synced recently)")
                        shouldSync = true
                    }
                } catch {
                    Logger.warning("⚠️ Error checking song existence: \(error.localizedDescription) - forcing sync")
                    shouldSync = true
                }
            } else {
                // No firestoreId means new song - always sync
                Logger.debug("📝 Song '\(song.name)' has no firestoreId - will create new")
                shouldSync = true
            }
            
            guard shouldSync else { continue }
            
            do {
                Logger.debug("📤 Syncing song: \(song.name)")
                Logger.debug("   - lastSyncedAt: \(song.lastSyncedAt?.description ?? "nil")")
                Logger.debug("   - firestoreId: \(song.firestoreId ?? "nil")")
                Logger.debug("   - projectId: \(projectId)")
                
                // Check if this is an update to existing cloud song
                if let songId = song.firestoreId {
                    Logger.debug("🔄 Calling updateSong with:")
                    Logger.debug("   - projectId: \(projectId)")
                    Logger.debug("   - songId: \(songId)")
                    Logger.debug("   - name: \(song.name)")
                    
                    try await firestoreService.updateSong(
                        projectId: projectId,
                        songId: songId,
                        data: [
                            "name": song.name,
                            "artist": song.artist ?? "",
                            "notes": song.notes ?? "",
                            "status": song.status.rawValue,
                            "sortOrder": song.sortOrder
                        ]
                    )
                    
                    Logger.debug("✅ updateSong completed successfully")
                    
                    await MainActor.run {
                        song.needsUpload = false
                        song.lastSyncedAt = Date()
                        try? modelContext.save()
                    }
                    
                } else {
                    // New song - create in Firestore
                    Logger.debug("📤 Creating new song with createSong()")
                    Logger.debug("   - projectId: \(projectId)")
                    Logger.debug("   - song.name: \(song.name)")
                    
                    let firestoreId = try await firestoreService.createSong(
                        projectId: projectId,
                        song: song
                    )
                    
                    Logger.debug("✅ createSong completed, got firestoreId: \(firestoreId)")
                    
                    await MainActor.run {
                        song.firestoreId = firestoreId
                        song.needsUpload = false
                        song.lastSyncedAt = Date()
                        try? modelContext.save()
                    }
                }
                
                successCount += 1
                Logger.debug("✅ Successfully synced song: \(song.name)")
                
            } catch {
                failCount += 1
                Logger.error("❌ Failed to sync song '\(song.name)': \(error.localizedDescription)")
                Logger.error("❌ Full error: \(error)")
                Logger.error("❌ Error type: \(type(of: error))")
                // Keep needsUpload = true so it retries later
            }
        }
        
        Logger.debug("🎉 Song sync complete: \(successCount) uploaded, \(failCount) failed")
    }
    
    // MARK: - In-App Notifications
    
    private func showApprovalNotification(
        reviewerName: String,
        status: ApprovalStatus,
        mixName: String,
        songName: String,
        projectName: String
    ) {
        guard let notificationService = inAppNotificationService else { return }
        
        let title: String
        let message: String
        
        switch status {
        case .approved:
            title = "✅ Mix Approved"
            message = "\(reviewerName) approved \(mixName) in \(songName)"
        case .changesRequested:
            title = "🔄 Changes Requested"
            message = "\(reviewerName) requested changes to \(mixName) in \(songName)"
        case .pending:
            return // Don't notify for pending status
        }
        
        Task { @MainActor in
            notificationService.showNotification(
                type: .approvalStatusChanged,
                title: title,
                message: message
            )
        }
    }
}
