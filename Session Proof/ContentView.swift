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
    @Environment(NotificationService.self) private var notificationService
    
    @State private var hasSyncedOnce = false
    @State private var syncTimer: Task<Void, Never>?
    @State private var isPerformingInitialSync = false
    
    var body: some View {
        ZStack {
            ProjectListView()
            
            // Show loading overlay during initial sync
            if isPerformingInitialSync {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Syncing projects...")
                        .foregroundStyle(.white)
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .task {
                // Sync projects from cloud when user first logs in
                if !hasSyncedOnce, let userId = authService.currentUser?.id {
                    hasSyncedOnce = true
                    isPerformingInitialSync = true
                    print("🔄 Initial sync triggered for user: \(userId)")
                    
                    Task {
                        defer {
                            // Always hide loading indicator when done
                            Task { @MainActor in
                                isPerformingInitialSync = false
                            }
                        }
                        
                        do {
                            // Accept any pending invitations for this user (with timeout)
                            if let userEmail = authService.currentUser?.email {
                                try? await withTimeout(seconds: 10) {
                                    try await syncService.acceptPendingInvitations(
                                        userId: userId,
                                        userEmail: userEmail,
                                        modelContext: modelContext
                                    )
                                }
                            }
                            
                            // Sync user's projects (with timeout to prevent indefinite hang)
                            try await withTimeout(seconds: 30) {
                                try await syncService.syncUserProjectsFromCloud(
                                    userId: userId,
                                    modelContext: modelContext
                                )
                            }
                            print("✅ Initial project sync completed")
                            
                            // Sync user's organization
                            try await syncService.syncUserOrganization(
                                userId: userId,
                                modelContext: modelContext
                            )
                            print("✅ Initial organization sync completed")
                            
                            // Refresh FCM token now that user is authenticated
                            // This ensures the token gets saved even if it arrived before authentication
                            await notificationService.refreshFCMToken()
                            print("✅ FCM token refreshed after authentication")
                            
                            // One-time migration for existing beta users
                            if let user = authService.currentUser,
                               user.subscriptionStatus == nil,
                               user.isProducer {
                                let trialStart = Date()
                                let trialEnd = Calendar.current.date(byAdding: .day, value: 30, to: trialStart)!
                                
                                try? await authService.updateSubscriptionStatus(
                                    tier: "producer",
                                    status: "trial",
                                    trialStartedAt: trialStart,
                                    trialEndsAt: trialEnd
                                )
                                print("✅ Migrated beta user to 30-day trial")
                            }
                            
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
                            
                            // Auto-sync any unsyncced comments
                            await syncQueueService.processPendingSyncs(modelContext: modelContext)
                            print("✅ Auto-sync of unsyncced comments completed")
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerBackgroundSync"))) { notification in
                // Handle background sync triggered by push notification
                guard let userId = authService.currentUser?.id else { return }

                let notificationType = notification.userInfo?["notificationType"] as? String ?? "unknown"
                print("🔄 Triggered background sync from notification: \(notificationType)")

                Task {
                    do {
                        try await syncService.syncUserProjectsFromCloud(
                            userId: userId,
                            modelContext: modelContext
                        )
                        print("✅ Background sync completed after notification: \(notificationType)")
                    } catch {
                        print("❌ Background sync failed: \(error.localizedDescription)")
                    }
                }
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
    
    /// Execute an async operation with a timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private struct TimeoutError: Error {}
}

#Preview {
    ContentView()
        .modelContainer(for: Project.self, inMemory: true)
}
