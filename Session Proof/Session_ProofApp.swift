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
    @State private var authService: AuthenticationService
    @State private var firestoreService: FirestoreService
    @State private var cloudStorageService: CloudStorageService
    @State private var syncService: ProjectSyncService
    
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
        // Configure Firebase FIRST before creating any services
        FirebaseApp.configure()
        
        // Now initialize services
        let auth = AuthenticationService()
        let firestore = FirestoreService()
        let cloudStorage = CloudStorageService()
        let sync = ProjectSyncService(
            firestoreService: firestore,
            cloudStorageService: cloudStorage,
            authService: auth
        )
        
        _authService = State(initialValue: auth)
        _firestoreService = State(initialValue: firestore)
        _cloudStorageService = State(initialValue: cloudStorage)
        _syncService = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(cloudStorageService)
                    .environment(syncService)
            } else {
                AuthenticationView()
                    .environment(authService)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
