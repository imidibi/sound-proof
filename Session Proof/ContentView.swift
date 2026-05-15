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
                    }
                }
                
                // Update pending sync count on app start
                await syncQueueService.updatePendingCount(modelContext: modelContext)
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Project.self, inMemory: true)
}
