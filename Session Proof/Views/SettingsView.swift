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
    @Environment(ProjectSyncService.self) private var syncService
    
    @Query private var organizations: [Organization]
    
    @State private var isLoggingOut = false
    @State private var showingLogoutConfirmation = false
    @State private var showingOrganizationManagement = false
    @State private var isSyncing = false
    @State private var lastSyncTime: Date?
    
    // Profile editing
    @State private var editedDisplayName = ""
    @State private var editedEmail = ""
    @State private var editedRole: UserRole = .artist
    @State private var isEditingProfile = false
    @State private var isSavingProfile = false
    
    private var userOrganization: Organization? {
        guard let userId = authService.currentUser?.id else {
            return nil
        }
        
        return organizations.first { $0.memberIds.contains(userId) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let user = authService.currentUser {
                        if isEditingProfile {
                            // Editable fields
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Display Name", text: $editedDisplayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("email@example.com", text: $editedEmail)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.emailAddress)
                                    #if os(iOS)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    #endif
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Role")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Role", selection: $editedRole) {
                                    ForEach([UserRole.producer, .studio, .artist], id: \.self) { role in
                                        Text(role.rawValue.capitalized).tag(role)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            // Save and Cancel buttons
                            HStack {
                                Button("Cancel") {
                                    isEditingProfile = false
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Save") {
                                    Task {
                                        await saveProfileChanges()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSavingProfile || editedDisplayName.isEmpty || editedEmail.isEmpty)
                            }
                        } else {
                            // Read-only display
                            LabeledContent("Name", value: user.displayName)
                            LabeledContent("Email", value: user.email)
                            LabeledContent("Role", value: user.role.rawValue.capitalized)
                            
                            if let orgName = user.organizationName {
                                LabeledContent("Organization", value: orgName)
                            }
                            
                            Button("Edit Profile") {
                                startEditingProfile()
                            }
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
                    Button {
                        Task {
                            await syncNow()
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            
                            if isSyncing {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSyncing)
                    
                    if let lastSync = lastSyncTime {
                        LabeledContent("Last Synced") {
                            Text(lastSync, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sync")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    Text("Manually sync your projects and organization with the cloud.")
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
    
    private func syncNow() async {
        guard let userId = authService.currentUser?.id,
              let userEmail = authService.currentUser?.email else {
            return
        }
        
        isSyncing = true
        
        do {
            print("🔄 Manual sync initiated")
            
            // Accept pending invitations
            try await syncService.acceptPendingInvitations(
                userId: userId,
                userEmail: userEmail,
                modelContext: modelContext
            )
            
            // Sync projects
            try await syncService.syncUserProjectsFromCloud(
                userId: userId,
                modelContext: modelContext
            )
            
            // Sync organization
            try await syncService.syncUserOrganization(
                userId: userId,
                modelContext: modelContext
            )
            
            await MainActor.run {
                lastSyncTime = Date()
                isSyncing = false
            }
            
            print("✅ Manual sync completed")
        } catch {
            print("❌ Manual sync failed: \(error)")
            await MainActor.run {
                isSyncing = false
            }
        }
    }
    
    private func signOut() async {
        isLoggingOut = true
        
        do {
            // Sign out from Firebase
            try authService.signOut()
            
            // Clear all local SwiftData to prevent data leakage between users
            await MainActor.run {
                print("🗑️ Clearing all local data for user isolation...")
                
                // Delete all projects (cascade will delete songs, mixes, comments, reviewers, approvals)
                do {
                    let descriptor = FetchDescriptor<Project>()
                    let allProjects = try modelContext.fetch(descriptor)
                    for project in allProjects {
                        modelContext.delete(project)
                    }
                    
                    // Delete all organizations
                    let orgDescriptor = FetchDescriptor<Organization>()
                    let allOrganizations = try modelContext.fetch(orgDescriptor)
                    for organization in allOrganizations {
                        modelContext.delete(organization)
                    }
                    
                    // Save changes
                    try modelContext.save()
                    print("✅ All local data cleared - user isolation complete")
                } catch {
                    print("❌ Error clearing local data: \(error)")
                }
                
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
    
    private func startEditingProfile() {
        guard let user = authService.currentUser else { return }
        editedDisplayName = user.displayName
        editedEmail = user.email
        editedRole = user.role
        isEditingProfile = true
    }
    
    private func saveProfileChanges() async {
        guard let user = authService.currentUser else { return }
        
        isSavingProfile = true
        
        // Normalize email
        let normalizedEmail = editedEmail.lowercased().trimmingCharacters(in: .whitespaces)
        
        do {
            // Update user profile
            let updatedUser = User(
                id: user.id,
                email: normalizedEmail,
                displayName: editedDisplayName,
                role: editedRole,
                createdAt: user.createdAt,
                organizationId: user.organizationId,
                organizationName: user.organizationName
            )
            
            try await authService.updateUserProfile(user: updatedUser)
            
            await MainActor.run {
                isSavingProfile = false
                isEditingProfile = false
            }
            
            print("✅ Profile updated successfully")
        } catch {
            print("❌ Failed to update profile: \(error)")
            await MainActor.run {
                isSavingProfile = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
