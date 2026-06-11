//
//  InviteArtistSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/14/26.
//

import SwiftUI
import SwiftData

struct InviteArtistSheet: View {
    let project: Project
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSyncService.self) private var syncService
    @Environment(AuthenticationService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    
    @State private var artistName = ""
    @State private var artistEmail = ""
    @State private var role: ReviewerRole = .reviewer
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var existingUserFound: User?
    @State private var previousReviewers: [(email: String, name: String, projectCount: Int)] = []
    @State private var showingSuggestions = false
    @State private var invitationSent = false
    @State private var invitationLink = ""
    
    var canSave: Bool {
        !artistName.isEmpty && !artistEmail.isEmpty && isValidEmail(artistEmail)
    }
    
    var body: some View {
        NavigationStack {
            Form {
Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $artistName, prompt: Text("Approver name"))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Email", text: $artistEmail, prompt: Text("email@example.com"))
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                #endif
                                .autocorrectionDisabled()
                            
                            // Show previous reviewers matching the typed email
                            if !artistEmail.isEmpty && !previousReviewers.isEmpty {
                                let matches = previousReviewers.filter { 
                                    $0.email.lowercased().contains(artistEmail.lowercased()) 
                                }
                                
                                if !matches.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Previously worked with:")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        
                                        ForEach(matches.prefix(3), id: \.email) { reviewer in
                                            Button {
                                                artistEmail = reviewer.email
                                                artistName = reviewer.name
                                                Task {
                                                    await checkForExistingUser(email: reviewer.email)
                                                }
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(reviewer.name)
                                                            .font(.caption)
                                                        Text(reviewer.email)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Text("\(reviewer.projectCount) project\(reviewer.projectCount > 1 ? "s" : "")")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.vertical, 4)
                                                .padding(.horizontal, 8)
                                                .background(Color.blue.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Approver Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    if let existingUser = existingUserFound {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Found existing user: \(existingUser.displayName). They'll be added to this project.")
                                .font(.caption)
                        }
                    } else {
                        Text("An invitation will be sent. They can accept it by signing in or creating an account.")
                    }
                }
                .onChange(of: artistEmail) { _, newValue in
                    Task {
                        await checkForExistingUser(email: newValue)
                    }
                }
                .task {
                    await loadPreviousReviewers()
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Invite Approver")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if existingUserFound != nil {
                        // Show "Add" button for existing users
                        Button {
                            Task {
                                await addExistingUser()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Add")
                            }
                        }
                        .disabled(!canSave || isSaving)
                    } else {
                        // Show "Invite" button for new users
                        Button {
                            Task {
                                await inviteArtist()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Invite")
                            }
                        }
                        .disabled(!canSave || isSaving)
                    }
                }
                
                // Add secondary "Invite" button when existing user is found
                if existingUserFound != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await inviteArtist()
                            }
                        } label: {
                            Text("Invite")
                        }
                        .disabled(!canSave || isSaving)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500)
        #endif
    }
    
    private func loadPreviousReviewers() async {
        guard let userId = authService.currentUser?.id else {
            return
        }
        
        do {
            let reviewers = try await firestoreService.getAllReviewersForProducer(userId: userId)
            await MainActor.run {
                previousReviewers = reviewers
                print("📋 Loaded \(reviewers.count) previous reviewers")
            }
        } catch {
            print("⚠️ Failed to load previous reviewers: \(error)")
        }
    }
    
    private func checkForExistingUser(email: String) async {
        guard isValidEmail(email) else {
            await MainActor.run {
                existingUserFound = nil
            }
            return
        }
        
        do {
            let user = try await authService.getUserByEmail(email: email.lowercased().trimmingCharacters(in: .whitespaces))
            await MainActor.run {
                existingUserFound = user
                // Pre-fill name if found
                if let user = user, artistName.isEmpty {
                    artistName = user.displayName
                }
            }
        } catch {
            await MainActor.run {
                existingUserFound = nil
            }
        }
    }
    
    private func addExistingUser() async {
        print("➕ Adding existing user directly without email invitation...")
        errorMessage = nil
        
        await MainActor.run {
            isSaving = true
        }
        
        let cleanEmail = artistEmail.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Check if this email is already a reviewer on this project
        let existingReviewer = project.reviewers.first { reviewer in
            reviewer.email.lowercased() == cleanEmail
        }
        
        if existingReviewer != nil {
            await MainActor.run {
                errorMessage = "This email address is already invited to this project"
                isSaving = false
            }
            return
        }
        
        // Create reviewer without invitation token (they're already registered)
        let reviewer = Reviewer(
            displayName: artistName,
            email: cleanEmail,
            userId: existingUserFound?.id,
            role: role,
            inviteStatus: .accepted, // Mark as accepted since they're already in the system
            acceptedAt: Date()
        )
        
        print("📝 Created reviewer object for existing user: \(reviewer.displayName)")
        if let userId = existingUserFound?.id {
            print("✅ Linked to existing user: \(userId)")
        }
        
        // Set project relationship
        reviewer.project = project
        
        // Save to local database
        do {
            await MainActor.run {
                modelContext.insert(reviewer)
            }
            try await MainActor.run {
                try modelContext.save()
            }
            print("💾 Reviewer saved to local database")
        } catch {
            print("❌ Failed to save reviewer locally: \(error)")
            await MainActor.run {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
            return
        }
        
        // Sync to Firestore (non-blocking - continue even if it fails)
        if let firestoreId = project.firestoreId {
            print("☁️ Attempting Firestore sync...")
            do {
                try await syncService.addReviewer(
                    projectId: firestoreId,
                    reviewer: reviewer
                )
                print("✓ Reviewer synced to Firestore successfully")
            } catch {
                // Log the error but don't block the UI
                print("⚠️ Firestore sync failed (reviewer saved locally): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ No Firestore ID, skipping cloud sync")
        }
        
        // Always dismiss and reset state
        print("✅ Dismissing invite sheet")
        await MainActor.run {
            isSaving = false
            dismiss()
        }
    }
    
    private func inviteArtist() async {
        print("🎯 Starting invite artist flow...")
        errorMessage = nil
        
        await MainActor.run {
            isSaving = true
        }
        
        let cleanEmail = artistEmail.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Check if this email is already a reviewer on this project
        let existingReviewer = project.reviewers.first { reviewer in
            reviewer.email.lowercased() == cleanEmail
        }
        
        if existingReviewer != nil {
            await MainActor.run {
                errorMessage = "This email address is already invited to this project"
                isSaving = false
            }
            return
        }
        
        // Generate unique invitation token
        let invitationToken = UUID().uuidString
        
        // Create reviewer with invitation token
        let reviewer = Reviewer(
            displayName: artistName,
            email: cleanEmail,
            userId: existingUserFound?.id, // Link to existing user if found
            role: role,
            inviteStatus: .sent,
            invitationToken: invitationToken,
            invitedAt: Date()
        )
        
        print("📝 Created reviewer object: \(reviewer.displayName)")
        if let userId = existingUserFound?.id {
            print("✅ Linked to existing user: \(userId)")
        } else {
            print("📧 New user - invitation token: \(invitationToken)")
        }
        
        // Set project relationship
        reviewer.project = project
        
        print("🔗 Set project relationship")
        
        // Save to local database
        do {
            await MainActor.run {
                modelContext.insert(reviewer)
            }
            try await MainActor.run {
                try modelContext.save()
            }
            print("💾 Reviewer saved to local database")
        } catch {
            print("❌ Failed to save reviewer locally: \(error)")
            await MainActor.run {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
            return
        }
        
        // Send invitation email
        print("📧 Sending invitation email to: \(cleanEmail)")
        await sendInvitationEmail(
            to: cleanEmail,
            artistName: artistName,
            projectName: project.name,
            invitationToken: invitationToken
        )
        
        // Sync to Firestore (non-blocking - continue even if it fails)
        if let firestoreId = project.firestoreId {
            print("☁️ Attempting Firestore sync...")
            do {
                try await syncService.addReviewer(
                    projectId: firestoreId,
                    reviewer: reviewer
                )
                print("✓ Reviewer synced to Firestore successfully")
                print("📬 Invitation token: \(invitationToken)")
            } catch {
                // Log the error but don't block the UI
                print("⚠️ Firestore sync failed (reviewer saved locally): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ No Firestore ID, skipping cloud sync")
        }
        
        // Always dismiss and reset state
        print("✅ Dismissing invite sheet")
        await MainActor.run {
            isSaving = false
            dismiss()
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Z0-9a-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func sendInvitationEmail(
        to email: String,
        artistName: String,
        projectName: String,
        invitationToken: String
    ) async {
        guard let producerName = authService.currentUser?.displayName else {
            return
        }
        
        // Create deep link for invitation
        // Format: approvl://invite?token=<token>&email=<email>
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        let deepLink = "approvl://invite?token=\(invitationToken)&email=\(encodedEmail)"
        
        await MainActor.run {
            invitationLink = deepLink
        }
        
        // Create email content
        let subject = "\(producerName) invited you to review \(projectName)"
        let body = """
        Hi \(artistName),

        \(producerName) has invited you to review the project "\(projectName)" on Approvl.

        To get started:
        1. Download Approvl from the App Store
        2. Create an account using this email address: \(email)
        3. Sign in and you'll automatically see the project

        Thanks,
        The Approvl Team
        """
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        
        // Open mail client with pre-filled email
        if let mailtoURL = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)") {
            #if os(iOS)
            await MainActor.run {
                UIApplication.shared.open(mailtoURL)
            }
            #elseif os(macOS)
            await MainActor.run {
                _ = NSWorkspace.shared.open(mailtoURL)
            }
            #endif
            
            await MainActor.run {
                invitationSent = true
            }
        }
    }
}

#Preview {
    InviteArtistSheet(project: Project(
        name: "Test Project",
        clientName: "Test Client",
        ownerUserID: "user1"
    ))
    .environment(ProjectSyncService(
        firestoreService: FirestoreService(),
        cloudStorageService: CloudStorageService(),
        authService: AuthenticationService()
    ))
    .modelContainer(for: Project.self, inMemory: true)
}
