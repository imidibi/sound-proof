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
                            try await syncService.syncUserProjectsFromCloud(
                                userId: userId,
                                modelContext: modelContext
                            )
                            print("✅ Initial sync completed")
                        } catch {
                            print("❌ Initial sync failed: \(error)")
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
