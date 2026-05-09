//
//  Session_ProofApp.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct Session_ProofApp: App {
    @State private var authService = AuthenticationService()
    @State private var firestoreService = FirestoreService()
    @State private var cloudStorageService = CloudStorageService()
    @State private var syncService: ProjectSyncService?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Song.self,
            Mix.self,
            Comment.self,
            Reviewer.self,
            Approval.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(cloudStorageService)
                    .environment(getSyncService())
            } else {
                AuthenticationView()
                    .environment(authService)
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func getSyncService() -> ProjectSyncService {
        if syncService == nil {
            syncService = ProjectSyncService(
                firestoreService: firestoreService,
                cloudStorageService: cloudStorageService,
                authService: authService
            )
        }
        return syncService!
    }
}
