//
//  ContentView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(ProjectSyncService.self) private var syncService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(SyncQueueService.self) private var syncQueueService
    
    @State private var hasSyncedOnce = false
    @State private var syncTimer: Task<Void, Never>?
    
    var body: some View {
        ProjectListView()
            .task {
                // Sync projects from cloud when user first logs in
                if !hasSyncedOnce, let userId = authService.currentUser?.id {
                    hasSyncedOnce = true
                    print("🔄 Initial sync triggered for user: \(userId)")
                    
                    Task {
                        do {
                            // Accept any pending invitations for this user
                            if let userEmail = authService.currentUser?.email {
                                try await syncService.acceptPendingInvitations(
                                    userId: userId,
                                    userEmail: userEmail,
                                    modelContext: modelContext
                                )
                            }
                            
                            // Sync user's projects
                            try await syncService.syncUserProjectsFromCloud(
                                userId: userId,
                                modelContext: modelContext
                            )
                            print("✅ Initial project sync completed")
                            
                            // Sync user's organization
                            try await syncService.syncUserOrganization(
                                userId: userId,
                                modelContext: modelContext
                            )
                            print("✅ Initial organization sync completed")
                            
                            // Auto-sync any unsyncced songs
                            do {
                                try await syncService.syncUnsyncedSongsToCloud(
                                    modelContext: modelContext
                                )
                                print("✅ Auto-sync of unsyncced songs completed")
                            } catch {
                                print("❌ Auto-sync of songs failed: \(error)")
                            }
                            
                            // Auto-sync any unsyncced mixes
                            do {
                                try await syncService.syncUnsyncedMixesToCloud(
                                    modelContext: modelContext
                                )
                                print("✅ Auto-sync of unsyncced mixes completed")
                            } catch {
                                print("❌ Auto-sync failed: \(error)")
                            }
                            
                            // Auto-sync any unsyncced approvals
                            do {
                                try await syncService.syncUnsyncedApprovalsToCloud(
                                    modelContext: modelContext
                                )
                                print("✅ Auto-sync of unsyncced approvals completed")
                            } catch {
                                print("❌ Auto-sync of approvals failed: \(error)")
                            }
                        } catch {
                            print("❌ Initial sync failed: \(error)")
                        }
                    }
                }
                
                // Setup network monitoring for automatic sync on reconnect
                networkMonitor.onConnectionRestored = {
                    Task {
                        print("🔄 Network restored - processing pending syncs")
                        await syncQueueService.processPendingSyncs(modelContext: modelContext)
                        
                        // Also auto-sync any unsyncced songs when network returns
                        do {
                            try await syncService.syncUnsyncedSongsToCloud(modelContext: modelContext)
                            print("✅ Auto-sync of songs on network restore completed")
                        } catch {
                            print("❌ Auto-sync of songs on network restore failed: \(error)")
                        }
                        
                        // Also auto-sync any unsyncced mixes when network returns
                        do {
                            try await syncService.syncUnsyncedMixesToCloud(modelContext: modelContext)
                            print("✅ Auto-sync on network restore completed")
                        } catch {
                            print("❌ Auto-sync on network restore failed: \(error)")
                        }
                        
                        // Auto-sync any unsyncced approvals when network returns
                        do {
                            try await syncService.syncUnsyncedApprovalsToCloud(modelContext: modelContext)
                            print("✅ Auto-sync of approvals on network restore completed")
                        } catch {
                            print("❌ Auto-sync of approvals on network restore failed: \(error)")
                        }
                    }
                }
                
                // Update pending sync count on app start
                await syncQueueService.updatePendingCount(modelContext: modelContext)
                
                // Start periodic background sync timer
                startPeriodicSync()
            }
            .onDisappear {
                // Cancel sync timer when view disappears
                syncTimer?.cancel()
            }
    }
    
    // MARK: - Periodic Background Sync
    
    private func startPeriodicSync() {
        // Cancel any existing timer
        syncTimer?.cancel()
        
        // Start new periodic sync task
        syncTimer = Task {
            while !Task.isCancelled {
                // Wait 5 minutes between syncs
                try? await Task.sleep(for: .seconds(300))
                
                guard !Task.isCancelled else { break }
                
                // Only sync if user is authenticated and online
                guard authService.currentUser != nil,
                      networkMonitor.isConnected else {
                    print("⏸️ Skipping periodic sync - user not authenticated or offline")
                    continue
                }
                
                print("🔄 Starting periodic background sync...")
                
                // Sync unsyncced songs
                do {
                    try await syncService.syncUnsyncedSongsToCloud(modelContext: modelContext)
                    print("✅ Periodic song sync completed")
                } catch {
                    print("❌ Periodic song sync failed: \(error.localizedDescription)")
                }
                
                // Sync unsyncced mixes
                do {
                    try await syncService.syncUnsyncedMixesToCloud(modelContext: modelContext)
                    print("✅ Periodic sync completed")
                } catch {
                    print("❌ Periodic sync failed: \(error.localizedDescription)")
                }
                
                // Sync unsyncced approvals
                do {
                    try await syncService.syncUnsyncedApprovalsToCloud(modelContext: modelContext)
                    print("✅ Periodic approval sync completed")
                } catch {
                    print("❌ Periodic approval sync failed: \(error.localizedDescription)")
                }
                
                // Also sync projects from cloud to catch updates from other devices
                if let userId = authService.currentUser?.id {
                    do {
                        try await syncService.syncUserProjectsFromCloud(
                            userId: userId,
                            modelContext: modelContext
                        )
                        print("✅ Periodic project sync completed")
                    } catch {
                        print("❌ Periodic project sync failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Project.self, inMemory: true)
}
