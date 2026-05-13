//
//  SettingsView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/11/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    
    @State private var isLoggingOut = false
    @State private var showingLogoutConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let user = authService.currentUser {
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Role", value: user.role.rawValue.capitalized)
                    }
                } header: {
                    Text("Account")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack {
                            Text("Sign Out")
                            if isLoggingOut {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isLoggingOut)
                }
                
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                } header: {
                    Text("About")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Sign Out",
                isPresented: $showingLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400)
        #endif
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private func signOut() async {
        isLoggingOut = true
        
        do {
            try await authService.signOut()
            await MainActor.run {
                isLoggingOut = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isLoggingOut = false
                // Error handling could be improved with an alert
                print("Error signing out: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    SettingsView()
}
