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
    @State private var networkMonitor: NetworkMonitor
    @State private var syncQueueService: SyncQueueService
    
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
        let network = NetworkMonitor()
        let syncQueue = SyncQueueService(syncService: sync)
        
        _authService = State(initialValue: auth)
        _firestoreService = State(initialValue: firestore)
        _cloudStorageService = State(initialValue: cloudStorage)
        _syncService = State(initialValue: sync)
        _networkMonitor = State(initialValue: network)
        _syncQueueService = State(initialValue: syncQueue)
    }

    var body: some Scene {
        WindowGroup {
            if authService.isCheckingAuth {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authService.isAuthenticated {
                ContentView()
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(cloudStorageService)
                    .environment(syncService)
                    .environment(networkMonitor)
                    .environment(syncQueueService)
            } else {
                AuthenticationView()
                    .environment(authService)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
