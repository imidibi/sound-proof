//
//  NotificationDebugView.swift
//  Session Proof
//
//  Debug view to display FCM token information and test notifications
//

import SwiftUI
import UserNotifications

struct NotificationDebugView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(FirestoreService.self) private var firestoreService
    
    @State private var savedTokens: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        NavigationStack {
            List {
                // Current Session Info
                Section("Current Session") {
                    if let userId = authService.currentUser?.id {
                        LabeledContent("User ID", value: userId)
                    }
                    if let email = authService.currentUser?.email {
                        LabeledContent("Email", value: email)
                    }
                    if let displayName = authService.currentUser?.displayName {
                        LabeledContent("Display Name", value: displayName)
                    }
                }
                
                // Current FCM Token
                Section("Current FCM Token") {
                    if let token = notificationService.fcmToken {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Token (first 40 chars):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(token.prefix(40)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Button("Copy Full Token") {
                                #if os(iOS)
                                UIPasteboard.general.string = token
                                #elseif os(macOS)
                                NSPasteboard.general.setString(token, forType: .string)
                                #endif
                                successMessage = "Token copied to clipboard"
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Text("No FCM token available")
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Authorization Status") {
                        switch notificationService.authorizationStatus {
                        case .notDetermined:
                            Text("Not Determined")
                                .foregroundStyle(.secondary)
                        case .denied:
                            Text("Denied")
                                .foregroundStyle(.red)
                        case .authorized:
                            Text("Authorized")
                                .foregroundStyle(.green)
                        case .provisional:
                            Text("Provisional")
                                .foregroundStyle(.orange)
                        #if os(iOS)
                        case .ephemeral:
                            Text("Ephemeral")
                                .foregroundStyle(.orange)
                        #endif
                        @unknown default:
                            Text("Unknown")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Saved Tokens in Firestore
                Section {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    } else if savedTokens.isEmpty {
                        Text("No tokens saved in Firestore")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(savedTokens.enumerated()), id: \.offset) { index, token in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Token \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(token.prefix(40)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Saved Tokens in Firestore")
                        Spacer()
                        Button("Refresh") {
                            Task {
                                await loadSavedTokens()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                // Actions
                Section("Actions") {
                    Button("Refresh FCM Token") {
                        Task {
                            await notificationService.refreshFCMToken()
                            successMessage = "Token refresh requested"
                            // Wait a moment then reload
                            try? await Task.sleep(for: .seconds(1))
                            await loadSavedTokens()
                        }
                    }
                    
                    Button("Request Notification Permission") {
                        Task {
                            let granted = await notificationService.requestPermissions()
                            if granted {
                                successMessage = "Notification permission granted"
                            } else {
                                errorMessage = "Notification permission denied"
                            }
                        }
                    }
                }
                
                // Status Messages
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Notification Debug")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadSavedTokens()
            }
            .refreshable {
                await loadSavedTokens()
            }
        }
    }
    
    private func loadSavedTokens() async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        do {
            let tokens = try await firestoreService.getUserFCMTokens(userId: userId)
            await MainActor.run {
                self.savedTokens = tokens
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading tokens: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

#Preview {
    NotificationDebugView()
        .environment(AuthenticationService())
        .environment(NotificationService(
            authService: AuthenticationService(),
            firestoreService: FirestoreService()
        ))
        .environment(FirestoreService())
}
