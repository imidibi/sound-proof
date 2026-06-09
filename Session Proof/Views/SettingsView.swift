//
//  SettingsView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/11/26.
//

import SwiftUI
import SwiftData
import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(ProjectSyncService.self) private var syncService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionService.self) private var subscriptionService
    
    @Query private var organizations: [Organization]
    
    @State private var isLoggingOut = false
    @State private var showingLogoutConfirmation = false
    @State private var showingOrganizationManagement = false
    @State private var isSyncing = false
    @State private var lastSyncTime: Date?
    @State private var showingHelp = false
    @State private var showingPaywall = false
    @State private var showingAppleIDLinking = false
    @State private var showLinkAppleIDAlert = false

    // Display preferences
    @AppStorage("showArchivedProjects") private var showArchivedProjects = false
    @AppStorage("projectSortOrder") private var projectSortOrder = "lastActivity"
    
    // Profile editing
    @State private var editedDisplayName = ""
    @State private var editedEmail = ""
    @State private var isEditingProfile = false
    @State private var isSavingProfile = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    
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
                            LabeledContent("Role", value: user.role == .artist ? "Approver" : user.role.rawValue.capitalized)
                            
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
                
                // Subscription section
                Section {
                    if let user = authService.currentUser {
                        // Current tier
                        HStack {
                            Label("Subscription", systemImage: "star.circle.fill")
                            Spacer()
                            if subscriptionService.isInTrial {
                                Text("Trial")
                                    .foregroundStyle(.orange)
                                    .fontWeight(.semibold)
                            } else if subscriptionService.hasActiveSubscription {
                                Text("Producer")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            } else {
                                Text("Free")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Trial status
                        if user.isInTrial, let daysRemaining = user.trialDaysRemaining {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(.orange)
                                Text("Trial ends in \(daysRemaining) \(daysRemaining == 1 ? "day" : "days")")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        
                        // Grace period warning
                        if user.isInGracePeriod, let daysRemaining = user.gracePeriodDaysRemaining {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Subscription Expired")
                                        .fontWeight(.semibold)
                                    Text("\(daysRemaining) days of read-only access remaining")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.orange)
                        }
                        
                        // Action buttons
                        if subscriptionService.hasActiveSubscription {
                            // Paid subscriber - show manage button to access App Store
                            Button {
                                subscriptionService.openManageSubscriptions()
                            } label: {
                                Label("Manage Subscription", systemImage: "gearshape")
                            }
                        } else {
                            // Free user or trial user - show upgrade/subscribe button
                            Button {
                                handleUpgradeToProducer()
                            } label: {
                                if subscriptionService.isInTrial {
                                    Label("Subscribe Now", systemImage: "star.fill")
                                } else {
                                    Label("Upgrade to Producer", systemImage: "arrow.up.circle.fill")
                                }
                            }

                            // Show "Link Apple ID" if Approver wants to become Producer
                            if let user = authService.currentUser,
                               !user.isProducer && !authService.hasAppleIDLinked {
                                Button {
                                    showLinkAppleIDAlert = true
                                } label: {
                                    Label("Link Apple ID", systemImage: "link")
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                        
                        // Restore purchases
                        Button {
                            Task {
                                await restorePurchases()
                            }
                        } label: {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Subscription")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    if let user = authService.currentUser {
                        if user.canCreateProjects {
                            Text("You have full access to all Producer features.")
                        } else {
                            Text("Upgrade to Producer to create projects and share your music for approval.")
                        }
                    }
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
                
                // Notifications section
                Section {
                    HStack {
                        Label("Push Notifications", systemImage: "bell.badge")
                        Spacer()
                        if notificationService.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    if !notificationService.isAuthorized {
                        Button {
                            Task {
                                await notificationService.requestPermissions()
                            }
                        } label: {
                            Label("Enable Notifications", systemImage: "bell.badge")
                        }
                    } else {
                        Button {
                            openNotificationSettings()
                        } label: {
                            Label("Notification Settings", systemImage: "gearshape")
                        }
                    }
                } header: {
                    Text("Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    if !notificationService.isAuthorized {
                        Text("Get notified when approvers comment or approve your mixes, or when new mixes are ready for review.")
                    } else {
                        Text("Notifications are enabled. You'll be notified of comments, approvals, and new mixes.")
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
                
                // Display preferences (only for producers)
                if let user = authService.currentUser, user.isProducer {
                    Section {
                        Toggle("Show Archived Projects", isOn: $showArchivedProjects)
                        
                        Picker("Project Sort Order", selection: $projectSortOrder) {
                            Text("Last Activity").tag("lastActivity")
                            Text("Alphabetical").tag("alphabetical")
                        }
                    } header: {
                        Text("Display")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    } footer: {
                        Text("Control how projects are displayed in your project list.")
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
                    Button(role: .destructive) {
                        showingDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Text("Delete Account")
                            if isDeletingAccount {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("Permanently delete your account and all associated data. This action cannot be undone.")
                        .foregroundStyle(.red)
                }
                
                Section {
                    Button {
                        #if os(iOS)
                        showingHelp = true
                        #elseif os(macOS)
                        showHelpWindow()
                        #endif
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    
                    Button {
                        if let url = URL(string: "mailto:support@studioguru.net?subject=Approvl%20Support") {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #elseif os(macOS)
                            NSWorkspace.shared.open(url)
                            #endif
                        }
                    } label: {
                        Label("Support & Bug Reports", systemImage: "envelope")
                    }
                    
                    #if DEBUG
                    NavigationLink {
                        NotificationDebugView()
                    } label: {
                        Label("Notification Debug", systemImage: "ladybug")
                    }
                    #endif
                } header: {
                    Text("Support")
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
            .confirmationDialog(
                "Delete Account",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all associated data including projects, mixes, and comments. This action cannot be undone.\n\nNote: If you recently signed in, you may need to sign out and sign back in before deleting your account.")
            }
            .alert("Error Deleting Account", isPresented: .constant(deleteAccountError != nil)) {
                Button("OK") {
                    deleteAccountError = nil
                }
            } message: {
                if let error = deleteAccountError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingOrganizationManagement) {
                OrganizationManagementView()
                    .environment(firestoreService)
            }
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environment(subscriptionService)
                    .environment(authService)
            }
            .sheet(isPresented: $showingAppleIDLinking) {
                AppleIDLinkingSheet()
                    .environment(authService)
            }
            .alert("Link Apple ID Required", isPresented: $showLinkAppleIDAlert) {
                Button("Link Now") {
                    showingAppleIDLinking = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To become a Producer and manage subscriptions, you need to link your Apple ID to your account. This allows you to purchase subscriptions while keeping your current login.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400)
        #endif
    }
    
    #if os(macOS)
    private func showHelpWindow() {
        let helpView = HelpView()
        let hostingController = NSHostingController(rootView: helpView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Approvl Help"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    #endif
    
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
    
    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    private func handleUpgradeToProducer() {
        guard let user = authService.currentUser else { return }

        // Check if user is already a producer
        if user.isProducer {
            // Already producer, just show paywall for subscription
            showingPaywall = true
            return
        }

        // Approver wants to become producer
        // Check if Apple ID is linked
        if authService.hasAppleIDLinked {
            // Has Apple ID, can proceed to upgrade
            showingPaywall = true
        } else {
            // Needs to link Apple ID first
            showLinkAppleIDAlert = true
        }
    }

    private func signOut() async {
        isLoggingOut = true
        
        do {
            // Delete FCM token before signing out
            await notificationService.deleteFCMToken()
            
            // Sign out from Firebase
            try authService.signOut()
            
            // Dismiss sheet BEFORE clearing data to avoid SwiftUI accessing deleted objects
            await MainActor.run {
                dismiss()
            }
            
            // Small delay to let sheet dismiss animation complete
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
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
        isEditingProfile = true
    }
    
    private func saveProfileChanges() async {
        guard let user = authService.currentUser else { return }
        
        isSavingProfile = true
        
        // Normalize email
        let normalizedEmail = editedEmail.lowercased().trimmingCharacters(in: .whitespaces)
        
        do {
            // Update user profile (keep existing role - users cannot change their own role)
            let updatedUser = User(
                id: user.id,
                email: normalizedEmail,
                displayName: editedDisplayName,
                role: user.role,  // Keep existing role, don't allow changes
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
    
    private func restorePurchases() async {
        do {
            try await subscriptionService.restorePurchases()
            
            // Sync to Firestore
            try await authService.updateSubscriptionStatus(
                tier: subscriptionService.subscriptionTier.rawValue,
                status: subscriptionService.subscriptionStatus.rawValue,
                trialStartedAt: subscriptionService.isInTrial ? subscriptionService.trialEndDate?.addingTimeInterval(-14 * 24 * 60 * 60) : nil,
                trialEndsAt: subscriptionService.trialEndDate,
                subscriptionExpiresAt: subscriptionService.subscriptionExpiryDate,
                gracePeriodEndsAt: subscriptionService.gracePeriodEndDate
            )
            
            print("✅ Purchases restored and synced")
        } catch {
            print("❌ Failed to restore purchases: \(error.localizedDescription)")
        }
    }
    
    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil
        
        do {
            // Delete FCM token first
            await notificationService.deleteFCMToken()
            
            // Delete account from Firebase
            try await authService.deleteAccount()
            
            // Dismiss sheet BEFORE clearing data to avoid SwiftUI accessing deleted objects
            await MainActor.run {
                dismiss()
            }
            
            // Small delay to let sheet dismiss animation complete
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Clear all local SwiftData
            await MainActor.run {
                print("🗑️ Clearing all local data for user isolation...")
                
                do {
                    // Delete all projects (cascade will delete songs, mixes, comments, reviewers, approvals)
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
                
                isDeletingAccount = false
            }
            
            print("✅ Account deleted successfully")
        } catch {
            await MainActor.run {
                isDeletingAccount = false
                deleteAccountError = error.localizedDescription
                print("❌ Error deleting account: \(error.localizedDescription)")
            }
        }
    }
}

// Apple ID Linking Sheet
struct AppleIDLinkingSheet: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var isLinking = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Link Apple ID")
                        .font(.title2.bold())

                    Text("Link your Apple ID to enable Producer features and subscription management while keeping your current login method.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                SignInWithAppleButton(
                    onRequest: { request in
                        let preparedRequest = authService.prepareSignInWithAppleRequest()
                        request.requestedScopes = []  // Don't request name/email for linking
                        request.nonce = preparedRequest.nonce
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            linkAppleID(authorization: authorization)

                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)

                if isLinking {
                    ProgressView("Linking...")
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Linking Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(errorMessage ?? "An error occurred while linking your Apple ID")
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("Continue") {
                    dismiss()
                }
            } message: {
                Text("Your Apple ID has been successfully linked. You can now upgrade to Producer and manage subscriptions.")
            }
        }
    }

    private func linkAppleID(authorization: ASAuthorization) {
        isLinking = true

        Task {
            do {
                try await authService.linkAppleID(authorization: authorization)

                await MainActor.run {
                    isLinking = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLinking = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
