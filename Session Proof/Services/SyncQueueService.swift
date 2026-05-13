//
//  SyncQueueService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/12/26.
//

import Foundation
import SwiftData
import Observation

@Observable
final class SyncQueueService {
    private var syncService: ProjectSyncService
    private var isSyncing = false
    
    var pendingSyncCount = 0
    
    init(syncService: ProjectSyncService) {
        self.syncService = syncService
    }
    
    // Process all pending syncs
    func processPendingSyncs(modelContext: ModelContext) async {
        guard !isSyncing else {
            print("⏳ Sync already in progress, skipping")
            return
        }
        
        isSyncing = true
        print("🔄 Starting sync queue processing...")
        
        do {
            // Fetch all comments that need syncing
            let descriptor = FetchDescriptor<Comment>(
                predicate: #Predicate { comment in
                    comment.needsSync == true
                }
            )
            
            let pendingComments = try modelContext.fetch(descriptor)
            pendingSyncCount = pendingComments.count
            
            guard !pendingComments.isEmpty else {
                print("✅ No pending syncs")
                isSyncing = false
                return
            }
            
            print("📤 Found \(pendingComments.count) comments needing sync")
            
            for comment in pendingComments {
                await syncComment(comment, modelContext: modelContext)
            }
            
            print("✅ Sync queue processing complete")
        } catch {
            print("❌ Error fetching pending syncs: \(error)")
        }
        
        isSyncing = false
    }
    
    private func syncComment(_ comment: Comment, modelContext: ModelContext) async {
        // Check if comment has required relationships
        guard let mix = comment.mix,
              let song = mix.song,
              let project = song.project,
              let projectId = project.firestoreId,
              let songId = song.firestoreId,
              let mixId = mix.firestoreId else {
            print("⚠️ Comment \(comment.id) not part of synced project - skipping")
            
            // Mark as synced even though we can't sync (it's local-only)
            await MainActor.run {
                comment.needsSync = false
                comment.syncError = "Not part of synced project"
            }
            return
        }
        
        // Update last sync attempt
        await MainActor.run {
            comment.lastSyncAttempt = Date()
        }
        
        do {
            // Get voice note URL if present
            let voiceNoteURL = comment.resolvedVoiceNoteURL
            
            try await syncService.syncComment(
                comment: comment,
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                voiceNoteURL: voiceNoteURL
            )
            
            // Mark as successfully synced
            await MainActor.run {
                comment.needsSync = false
                comment.syncError = nil
                pendingSyncCount = max(0, pendingSyncCount - 1)
                print("✅ Synced comment: \(comment.text.prefix(30))...")
            }
            
        } catch {
            print("❌ Failed to sync comment \(comment.id): \(error.localizedDescription)")
            
            await MainActor.run {
                comment.syncError = error.localizedDescription
                // Keep needsSync = true so we retry later
            }
        }
    }
    
    // Update pending count by querying the database
    func updatePendingCount(modelContext: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<Comment>(
                predicate: #Predicate { comment in
                    comment.needsSync == true
                }
            )
            
            let count = try modelContext.fetchCount(descriptor)
            
            await MainActor.run {
                pendingSyncCount = count
            }
        } catch {
            print("❌ Error updating pending sync count: \(error)")
        }
    }
}
