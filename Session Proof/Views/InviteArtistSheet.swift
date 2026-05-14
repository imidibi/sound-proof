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
    
    @State private var artistName = ""
    @State private var artistEmail = ""
    @State private var role: ReviewerRole = .reviewer
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var canSave: Bool {
        !artistName.isEmpty && !artistEmail.isEmpty && isValidEmail(artistEmail)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $artistName, prompt: Text("Artist or client name"))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                        
                        TextField("Email", text: $artistEmail, prompt: Text("email@example.com"))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Artist Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    Text("The artist will be able to join this project using the share code.")
                }
                
                Section {
                    Picker("Role", selection: $role) {
                        Text("Reviewer").tag(ReviewerRole.reviewer)
                        Text("Viewer").tag(ReviewerRole.viewer)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Permissions")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Reviewer: Can add comments and approve mixes")
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Viewer: Can only view and listen to mixes")
                        }
                    }
                    .font(.caption)
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
            .navigationTitle("Invite Artist")
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
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500)
        #endif
    }
    
    private func inviteArtist() async {
        errorMessage = nil
        isSaving = true
        
        defer { isSaving = false }
        
        // Create reviewer
        let reviewer = Reviewer(
            displayName: artistName,
            email: artistEmail.lowercased().trimmingCharacters(in: .whitespaces),
            role: role,
            inviteStatus: .sent
        )
        reviewer.project = project
        
        await MainActor.run {
            modelContext.insert(reviewer)
            try? modelContext.save()
        }
        
        // Sync to Firestore (non-blocking - continue even if it fails)
        if let firestoreId = project.firestoreId {
            do {
                try await syncService.addReviewer(
                    projectId: firestoreId,
                    reviewer: reviewer
                )
                
                // TODO: Send email invitation (future enhancement)
                
                print("✓ Reviewer synced to Firestore successfully")
            } catch {
                // Log the error but don't block the UI
                print("⚠️ Firestore sync failed (reviewer saved locally): \(error.localizedDescription)")
                
                // Only show error if it's not a permissions issue
                // Permissions issues will be resolved when Firestore rules are updated
                if !error.localizedDescription.contains("PERMISSION_DENIED") {
                    await MainActor.run {
                        errorMessage = "Reviewer added locally, but cloud sync failed. They may not appear for other users until you have proper permissions."
                    }
                    return
                }
            }
        }
        
        await MainActor.run {
            dismiss()
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
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
