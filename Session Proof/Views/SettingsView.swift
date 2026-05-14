//
//  SettingsView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/11/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @Query private var organizations: [Organization]
    
    @State private var isLoggingOut = false
    @State private var showingLogoutConfirmation = false
    @State private var showingOrganizationManagement = false
    
    private var userOrganization: Organization? {
        guard let userId = authService.currentUser?.id else {
            print("⚠️ No current user ID")
            return nil
        }
        
        print("🔍 Looking for organization for user: \(userId)")
        print("   Total organizations: \(organizations.count)")
        
        for org in organizations {
            print("   - Organization: \(org.name), Members: \(org.memberIds)")
        }
        
        let org = organizations.first { $0.memberIds.contains(userId) }
        if let org = org {
            print("✅ Found user's organization: \(org.name)")
        } else {
            print("⚠️ No organization found for user")
        }
        
        return org
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let user = authService.currentUser {
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Role", value: user.role.rawValue.capitalized)
                        
                        if let orgName = user.organizationName {
                            LabeledContent("Organization", value: orgName)
                        }
                    }
                } header: {
                    Text("Account")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // Organization management (for studio owners and producers)
                if let user = authService.currentUser, user.isProducer {
                    Section {
                        // Show organization name if it exists
                        if let organization = userOrganization {
                            Text(organization.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        
                        Button {
                            showingOrganizationManagement = true
                        } label: {
                            if userOrganization != nil {
                                Label("Edit Organization", systemImage: "building.2")
                            } else {
                                Label("Add Organization", systemImage: "building.2")
                            }
                        }
                    } header: {
                        Text("Organization")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
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
            .sheet(isPresented: $showingOrganizationManagement) {
                OrganizationManagementView()
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
            try authService.signOut()
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
