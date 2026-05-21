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
        print("👂 Setting up comment listener for project: \(projectId), mix: \(mixId)")
        return firestoreService.listenToComments(projectId: projectId, mixId: mixId) { [weak self] documents in
            guard let self = self else { return }
            
            print("📬 Received \(documents.count) comment documents from Firestore")
            
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
            print("⚠️ Skipping comment with invalid UUID format: \(commentId)")
            return
        }
        
        print("📥 Processing comment from cloud: \(commentId)")
        
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
                    print("⚠️ Invalid comment data for \(commentId)")
                    print("   - timestamp: \(data["timestamp"] ?? "missing")")
                    print("   - text: \(data["text"] ?? "missing")")
                    print("   - authorId: \(data["authorId"] ?? "missing")")
                    print("   - authorName: \(data["authorName"] ?? "missing")")
                    print("   - Available keys: \(data.keys.joined(separator: ", "))")
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
                    print("✅ Comment synced from cloud: \(text.prefix(30))...")
                } catch {
                    print("❌ Failed to save comment: \(error)")
                }
            }
        } catch {
            print("❌ Error checking for existing comment: \(error)")
        }
    }
    
    // Public method for downloading voice notes on demand
    func downloadMissingVoiceNote(for comment: Comment) async -> Bool {
        guard let cloudURL = comment.voiceNoteCloudURL else {
            print("⚠️ No cloud URL available for voice note")
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
                print("⚠️ Invalid voice note URL")
                return
            }
            
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            
            await MainActor.run {
                comment.voiceNoteFileName = fileName
                print("✅ Voice note downloaded: \(fileName)")
            }
        } catch {
            print("❌ Failed to download voice note: \(error)")
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
            print("❌ Cannot sync: user email not available")
            throw NSError(domain: "ProjectSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "User email not available"])
        }
        
        print("🔄 Syncing projects from cloud for user: \(userId)")
        print("🆔 User ID being used for sync: '\(userId)'")
        print("📧 User email: '\(userEmail)'")
        
        do {
            // Get projects owned by this user
            let ownedProjects = try await firestoreService.getUserProjects(userId: userId)
            print("📦 Found \(ownedProjects.count) owned projects")
            
            // Get projects where user is a reviewer (with email fallback and backfill)
            let reviewerProjects = try await firestoreService.getProjectsWhereUserIsReviewer(userId: userId, userEmail: userEmail)
            print("📦 Found \(reviewerProjects.count) projects where user is a reviewer")
            
            // Combine and deduplicate projects
            var projectsMap: [String: [String: Any]] = [:]
            for (projectId, projectData) in ownedProjects {
                projectsMap[projectId] = projectData
            }
            for (projectId, projectData) in reviewerProjects {
                projectsMap[projectId] = projectData
            }
            
            let cloudProjects = Array(projectsMap)
            print("📦 Total unique projects to sync: \(cloudProjects.count)")
            
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
                } else {
                    print("✓ Project already exists locally: \(projectData["name"] ?? "Unknown")")
                    
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
                
                // Still sync mixes in case there are new ones or updates
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
                print("✓ Mix already exists locally: \(mixData["name"] ?? "Unknown")")
                
                // Timestamp-based conflict resolution
                if let existingMix = existingMixes.first {
                    // Check if cloud version is deleted
                    let isDeletedInCloud = mixData["isDeleted"] as? Bool ?? false
                    
                    if isDeletedInCloud && !existingMix.isDeleted {
                        print("🗑️ Mix deleted in cloud - marking local copy as deleted")
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
                        
                        print("   Local lastModifiedAt: \(localDate)")
                        print("   Cloud updatedAt: \(cloudDate)")
                        
                        // If local is newer and needs upload, skip cloud update
                        if existingMix.needsUpload && localDate > cloudDate {
                            print("   ℹ️ Local version is newer and needs upload - keeping local changes")
                            continue
                        }
                        
                        // If cloud is newer or same, update from cloud
                        if cloudDate >= localDate {
                            print("   🔄 Cloud version is newer or equal - updating from cloud")
                            
                            // Update mix properties from cloud
                            if let name = mixData["name"] as? String {
                                existingMix.name = name
                            }
                            
                            if let statusString = mixData["approvalStatus"] as? String,
                               let status = MixStatus(rawValue: statusString) {
                                if existingMix.approvalStatus != status {
                                    print("   🔄 Updating approval status: \(existingMix.approvalStatus.rawValue) → \(status.rawValue)")
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
                            print("   ✅ Mix updated from cloud")
                        }
                    } else {
                        // No timestamp in cloud - just update approval status as before
                        print("   ⚠️ No timestamp in cloud data - updating approval status only")
                        
                        if let statusString = mixData["approvalStatus"] as? String,
                           let status = MixStatus(rawValue: statusString),
                           existingMix.approvalStatus != status {
                            print("   🔄 Updating approval status: \(existingMix.approvalStatus.rawValue) → \(status.rawValue)")
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
        print("👂 Setting up reviewer listener for project: \(projectId)")
        return firestoreService.listenToReviewers(projectId: projectId) { [weak self] documents in
            guard let self = self else { return }
            
            print("📬 Received \(documents.count) reviewer documents from Firestore")
            
            Task { @MainActor in
                // Get all reviewer IDs from Firestore
                let firestoreReviewerIds = Set(documents.compactMap { UUID(uuidString: $0.documentID) })
                
                // Get all local reviewers for this project
                let localReviewers = project.reviewers
                
                // Remove local reviewers that no longer exist in Firestore
                for localReviewer in localReviewers {
                    if !firestoreReviewerIds.contains(localReviewer.id) {
                        print("🗑️ Removing deleted reviewer: \(localReviewer.displayName)")
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
                    print("✅ Reviewer sync completed")
                } catch {
                    print("❌ Error saving reviewer changes: \(error)")
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
        
        print("📥 Processing reviewer from cloud: \(reviewerId)")
        
        // Check if reviewer already exists locally
        let descriptor = FetchDescriptor<Reviewer>(
            predicate: #Predicate { reviewer in
                reviewer.id == reviewerUUID
            }
        )
        
        do {
            let existingReviewers = try modelContext.fetch(descriptor)
            
            if existingReviewers.isEmpty {
                // Create new local reviewer
                guard let displayName = data["displayName"] as? String,
                      let email = data["email"] as? String,
                      let roleString = data["role"] as? String,
                      let role = ReviewerRole(rawValue: roleString) else {
                    print("⚠️ Invalid reviewer data for \(reviewerId)")
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
                    print("⚠️ Missing inviteStatus for reviewer \(reviewerId), defaulting to .accepted")
                    status = .accepted
                    needsFirestoreUpdate = true
                }
                
                let reviewer = Reviewer(
                    id: reviewerUUID,
                    displayName: displayName,
                    email: email,
                    userId: data["userId"] as? String,
                    role: role,
                    inviteStatus: status,
                    isKeyApprover: data["isKeyApprover"] as? Bool ?? false
                )
                
                if let acceptedTimestamp = data["acceptedAt"] as? Timestamp {
                    reviewer.acceptedAt = acceptedTimestamp.dateValue()
                }
                
                reviewer.project = project
                modelContext.insert(reviewer)
                try modelContext.save()
                
                print("✨ Created new reviewer from cloud: \(displayName)")
                
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
                            print("✅ Fixed missing inviteStatus in Firestore for \(displayName)")
                        } catch {
                            print("⚠️ Failed to update inviteStatus in Firestore: \(error)")
                        }
                    }
                }
            } else {
                print("✓ Reviewer already exists locally: \(data["displayName"] ?? "Unknown")")
            }
        } catch {
            print("❌ Error processing reviewer: \(error)")
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
        print("👂 Setting up approval listener for mix: \(mixId)")
        return firestoreService.setupApprovalsListener(
            projectId: projectId,
            songId: songId,
            mixId: mixId
        ) { [weak self] approvalDocs in
            guard let self = self else { return }
            
            print("📬 Received \(approvalDocs.count) approval documents from Firestore")
            
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
            print("⚠️ Invalid approval data")
            return
        }
        
        print("📥 Processing approval from cloud for user: \(reviewerUserId)")
        
        // Find the reviewer by userId
        guard let reviewer = project.reviewers.first(where: { $0.userId == reviewerUserId }) else {
            print("⚠️ Reviewer not found for userId: \(reviewerUserId)")
            return
        }
        
        // Check if approval already exists for this reviewer and mix
        let existingApproval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id })
        
        if let approval = existingApproval {
            // Update existing approval
            approval.status = status
            if let updatedTimestamp = approvalData["updatedAt"] as? Timestamp {
                approval.updatedAt = updatedTimestamp.dateValue()
            }
            print("✅ Updated existing approval for \(reviewer.displayName)")
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
            print("✅ Created new approval for \(reviewer.displayName)")
        }
        
        do {
            try modelContext.save()
        } catch {
            print("❌ Error saving approval: \(error)")
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
            
            print("📥 Syncing \(approvals.count) approvals for mix")
            
            for (_, approvalData) in approvals {
                await processApprovalFromCloud(
                    approvalData: approvalData,
                    mix: mix,
                    project: project,
                    modelContext: modelContext
                )
            }
        } catch {
            print("❌ Error syncing approvals: \(error)")
        }
    }
    
    private func syncProjectReviewers(
        projectId: String,
        project: Project,
        modelContext: ModelContext
    ) async throws {
        let cloudReviewers = try await firestoreService.getProjectReviewers(projectId: projectId)
        print("👥 Found \(cloudReviewers.count) reviewers for project")
        
        for (reviewerId, reviewerData) in cloudReviewers {
            // Convert reviewerId string to UUID
            guard let reviewerUUID = UUID(uuidString: reviewerId) else {
                // Skip userId-based documents (used for Firebase security rules)
                // These are intentionally created with userId as document ID for rule matching
                continue
            }
            
            // Check if reviewer already exists locally
            let descriptor = FetchDescriptor<Reviewer>(
                predicate: #Predicate { $0.id == reviewerUUID }
            )
            let existingReviewers = try modelContext.fetch(descriptor)
            
            if existingReviewers.isEmpty {
                print("✨ Creating new local reviewer: \(reviewerData["displayName"] ?? "Unknown")")
                
                guard let displayName = reviewerData["displayName"] as? String,
                      let email = reviewerData["email"] as? String,
                      let roleString = reviewerData["role"] as? String,
                      let role = ReviewerRole(rawValue: roleString) else {
                    print("⚠️ Invalid reviewer data for \(reviewerId)")
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
                    print("⚠️ Missing inviteStatus for reviewer \(reviewerId), defaulting to .accepted")
                    status = .accepted
                    needsFirestoreUpdate = true
                }
                
                let reviewer = Reviewer(
                    id: reviewerUUID,
                    displayName: displayName,
                    email: email,
                    userId: reviewerData["userId"] as? String,
                    role: role,
                    inviteStatus: status
                )
                
                if let acceptedTimestamp = reviewerData["acceptedAt"] as? Timestamp {
                    reviewer.acceptedAt = acceptedTimestamp.dateValue()
                }
                
                reviewer.project = project
                modelContext.insert(reviewer)
                try modelContext.save()
                
                print("📥 Reviewer synced: \(displayName)")
                
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
                            print("✅ Fixed missing inviteStatus in Firestore for \(displayName)")
                        } catch {
                            print("⚠️ Failed to update inviteStatus in Firestore: \(error)")
                        }
                    }
                }
            } else {
                print("✓ Reviewer already exists locally: \(reviewerData["displayName"] ?? "Unknown")")
            }
        }
    }
    
    // MARK: - Organization Sync
    
    func syncUserOrganization(
        userId: String,
        modelContext: ModelContext
    ) async throws {
        print("🏢 Starting organization sync for user: \(userId)")
        
        // Fetch organization from Firestore
        guard let (firestoreId, data) = try await firestoreService.getUserOrganization(userId: userId) else {
            print("ℹ️ No organization found in Firestore for user")
            return
        }
        
        print("☁️ Found organization in Firestore: \(firestoreId)")
        
        // Check if organization already exists locally
        print("🔍 Checking for existing local organization...")
        
        // First try to fetch all organizations and filter manually to avoid predicate issues
        let allOrgsDescriptor = FetchDescriptor<Organization>()
        let allOrganizations = try modelContext.fetch(allOrgsDescriptor)
        
        print("📊 Found \(allOrganizations.count) total local organizations")
        
        // Check by firestoreId or memberIds
        let existingOrganizations = allOrganizations.filter { org in
            if let orgFirestoreId = org.firestoreId, orgFirestoreId == firestoreId {
                print("✓ Match by firestoreId: \(orgFirestoreId)")
                return true
            }
            if org.memberIds.contains(userId) {
                print("✓ Match by memberIds")
                return true
            }
            return false
        }
        
        if let existingOrg = existingOrganizations.first {
            // Update existing organization
            print("📝 Updating existing organization: \(existingOrg.name)")
            
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
            print("✅ Organization updated from Firestore")
        } else {
            // Create new organization
            print("✨ Creating new organization from Firestore")
            
            guard let name = data["name"] as? String,
                  let typeString = data["type"] as? String,
                  let type = OrganizationType(rawValue: typeString) else {
                print("⚠️ Missing required organization data")
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
            print("✅ Organization created from Firestore: \(organization.name)")
        }
    }
    
    // MARK: - Auto-Accept Pending Invitations
    
    func acceptPendingInvitations(
        userId: String,
        userEmail: String,
        modelContext: ModelContext
    ) async throws {
        print("📬 Checking for pending invitations for: \(userEmail)")
        
        var invitationsAccepted = 0
        
        do {
            // Use collection group query to find all reviewers with this email across all projects
            let pendingInvitations = try await firestoreService.findPendingInvitationsByEmail(email: userEmail)
            print("🔍 Found \(pendingInvitations.count) reviewer record(s) with email: \(userEmail)")
            
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
                    print("✉️ Found pending invitation in project: \(invitation.projectId)")
                    print("   Reviewer email: \(invitation.data["email"] ?? ""), Document ID: \(invitation.reviewerId)")

                    // Update UUID-based reviewer document with userId and accept status if needed
                    if hasNoUserId {
                        try await firestoreService.updateReviewer(
                            projectId: invitation.projectId,
                            reviewerId: invitation.reviewerId,
                            data: [
                                "userId": userId,
                                "inviteStatus": ReviewerInviteStatus.accepted.rawValue,
                                "acceptedAt": Timestamp(date: Date())
                            ]
                        )
                    }

                    // Create userId-based reviewer document for security rules if it doesn't exist
                    if !userIdDocExists {
                        print("🔗 Creating userId-based reviewer document: \(userId)")
                        try await userIdReviewerRef.setData([
                            "email": invitation.data["email"] ?? userEmail,
                            "userId": userId,
                            "inviteStatus": ReviewerInviteStatus.accepted.rawValue,
                            "acceptedAt": Timestamp(date: Date())
                        ])
                    }

                    invitationsAccepted += 1
                    print("✅ Accepted invitation and linked userId for project: \(invitation.projectId)")
                } else {
                    print("✓ Reviewer already fully linked in project: \(invitation.projectId)")
                }
            }
            
            if invitationsAccepted > 0 {
                print("🎉 Accepted \(invitationsAccepted) pending invitation(s)")
            } else if pendingInvitations.isEmpty {
                print("ℹ️ No reviewer records found for email: \(userEmail)")
            } else {
                print("ℹ️ All reviewer records already have userId linked")
            }
        } catch {
            print("⚠️ Error checking for pending invitations: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Auto-Sync Unsyncced Mixes
    
    /// Automatically finds and uploads mixes that haven't been synced to the cloud yet
    /// This runs on app launch and network reconnect to ensure all local changes are backed up
    func syncUnsyncedMixesToCloud(modelContext: ModelContext) async throws {
        guard authService.currentUser?.id != nil else {
            print("⚠️ Cannot sync - no authenticated user")
            return
        }
        
        print("🔄 Starting auto-sync of unsyncced mixes...")
        
        // Query for mixes that need upload
        let descriptor = FetchDescriptor<Mix>(
            predicate: #Predicate<Mix> { mix in
                mix.needsUpload == true || (mix.isUploaded == false && mix.assetFileName != nil)
            }
        )
        
        let unsyncedMixes = try modelContext.fetch(descriptor)
        
        guard !unsyncedMixes.isEmpty else {
            print("✅ No unsyncced mixes found")
            return
        }
        
        print("📤 Found \(unsyncedMixes.count) mix(es) that need uploading")
        
        var successCount = 0
        var failCount = 0
        
        for mix in unsyncedMixes {
            // Get the song and project info
            guard let song = mix.song,
                  let project = song.project,
                  let projectId = project.firestoreId,
                  let songId = song.firestoreId else {
                print("⚠️ Mix '\(mix.name)' missing required project/song info - skipping")
                continue
            }
            
            // Handle deleted mixes - propagate deletion to cloud
            if mix.isDeleted {
                print("🗑️ Syncing deletion for mix: \(mix.name)")
                
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
                        print("✅ Deletion synced and local copy removed: \(mix.name)")
                        
                    } catch {
                        failCount += 1
                        print("❌ Failed to sync deletion for '\(mix.name)': \(error.localizedDescription)")
                    }
                } else {
                    // Mix was never uploaded, just delete locally
                    print("   ℹ️ Mix was never uploaded - removing locally only")
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
                print("⚠️ Mix '\(mix.name)' has no local file - skipping")
                continue
            }
            
            do {
                // Check if this is an update to existing cloud mix
                if let mixId = mix.firestoreId, mix.isUploaded {
                    print("🔄 Updating existing mix: \(mix.name)")
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
                    print("✅ Successfully updated: \(mix.name)")
                    
                } else {
                    // New mix - upload file and create in Firestore
                    print("📤 Uploading new mix: \(mix.name)")
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
                    print("✅ Successfully uploaded: \(mix.name)")
                }
                
            } catch {
                failCount += 1
                print("❌ Failed to sync '\(mix.name)': \(error.localizedDescription)")
                // Keep needsUpload = true so it retries later
            }
        }
        
        print("🎉 Auto-sync complete: \(successCount) uploaded, \(failCount) failed")
    }
}
