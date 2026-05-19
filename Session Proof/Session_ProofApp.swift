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
    @State private var pendingInvitationURL: URL?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Song.self,
            Mix.self,
            Comment.self,
            Reviewer.self,
            Approval.self,
            Organization.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            // If migration fails, try deleting the store and creating a new one
            // Data will be resynced from Firestore
            print("⚠️ Model container creation failed: \(error)")
            print("🔄 Attempting to reset local database - data will resync from Firestore...")
            
            do {
                let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
                try? FileManager.default.removeItem(at: storeURL)
                
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ Successfully created new model container")
                return container
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
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
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
            } else {
                AuthenticationView()
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(syncService)
                    .onOpenURL { url in
                        // Store URL to handle after authentication
                        pendingInvitationURL = url
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("📱 Received URL: \(url.absoluteString)")
        
        guard url.scheme == "sessionproof",
              url.host == "invite" else {
            print("⚠️ Invalid URL scheme or host")
            return
        }
        
        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            print("⚠️ No query parameters found")
            return
        }
        
        let token = queryItems.first(where: { $0.name == "token" })?.value
        let email = queryItems.first(where: { $0.name == "email" })?.value
        
        print("📧 Invitation - Token: \(token ?? "none"), Email: \(email ?? "none")")
        
        // If user is authenticated and this matches their email, accept the invitation
        if let userEmail = authService.currentUser?.email,
           let inviteEmail = email,
           userEmail.lowercased() == inviteEmail.lowercased() {
            
            Task {
                do {
                    try await syncService.acceptPendingInvitations(
                        userId: authService.currentUser?.id ?? "",
                        userEmail: userEmail,
                        modelContext: sharedModelContainer.mainContext
                    )
                    print("✅ Processed invitation from deep link")
                } catch {
                    print("❌ Error processing invitation: \(error)")
                }
            }
        } else {
            print("⚠️ Email mismatch or user not authenticated")
        }
    }
}
