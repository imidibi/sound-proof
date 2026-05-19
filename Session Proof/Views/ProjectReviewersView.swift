//
//  ProjectReviewersView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/14/26.
//

import SwiftUI
import SwiftData

struct ProjectReviewersView: View {
    @Bindable var project: Project
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(ProjectSyncService.self) private var syncService
    
    @State private var showingInviteSheet = false
    @State private var reviewerToDelete: Reviewer?
    @State private var showingDeleteConfirmation = false
    @State private var reviewerToEdit: Reviewer?
    @State private var showingEditSheet = false
    
    var sortedReviewers: [Reviewer] {
        project.reviewers.sorted { reviewer1, reviewer2 in
            // Owner first
            if reviewer1.role == .owner && reviewer2.role != .owner { return true }
            if reviewer2.role == .owner && reviewer1.role != .owner { return false }
            
            // Then by status (accepted before sent before not sent)
            if reviewer1.inviteStatus != reviewer2.inviteStatus {
                return reviewer1.inviteStatus.rawValue < reviewer2.inviteStatus.rawValue
            }
            
            // Then alphabetically
            return reviewer1.displayName < reviewer2.displayName
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedReviewers) { reviewer in
                        ReviewerRow(reviewer: reviewer, isProducerView: authService.currentUser?.isProducer == true)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if reviewer.role != .owner && authService.currentUser?.isProducer == true {
                                    Button(role: .destructive) {
                                        reviewerToDelete = reviewer
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .contextMenu {
                                if reviewer.role != .owner && authService.currentUser?.isProducer == true {
                                    Button {
                                        reviewerToEdit = reviewer
                                        showingEditSheet = true
                                    } label: {
                                        Label("Edit Reviewer", systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        toggleKeyApprover(reviewer)
                                    } label: {
                                        Label(
                                            reviewer.isKeyApprover ? "Remove as Key Approver" : "Set as Key Approver",
                                            systemImage: reviewer.isKeyApprover ? "crown.fill" : "crown"
                                        )
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        reviewerToDelete = reviewer
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Remove Reviewer", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Artists & Reviewers")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } footer: {
                    if project.reviewers.isEmpty {
                        Text("No artists invited yet. Tap the + button to invite artists to review this project.")
                    } else {
                        Text("Share Code: \(project.shareCode ?? "Not available")")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Manage Reviewers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if authService.currentUser?.isProducer == true {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingInviteSheet = true
                        } label: {
                            Label("Invite Artist", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingInviteSheet) {
                InviteArtistSheet(project: project)
            }
            .sheet(item: $reviewerToEdit) { reviewer in
                EditReviewerSheet(reviewer: reviewer, project: project)
            }
            .confirmationDialog(
                "Remove Reviewer",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let reviewer = reviewerToDelete {
                        removeReviewer(reviewer)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let reviewer = reviewerToDelete {
                    Text("Are you sure you want to remove \(reviewer.displayName) from this project?")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500)
        #endif
    }
    
    private func toggleKeyApprover(_ reviewer: Reviewer) {
        // If setting as key approver, remove key approver status from all other reviewers
        if !reviewer.isKeyApprover {
            for otherReviewer in project.reviewers {
                if otherReviewer.id != reviewer.id && otherReviewer.isKeyApprover {
                    otherReviewer.isKeyApprover = false
                    syncKeyApproverStatus(otherReviewer)
                }
            }
        }
        
        // Toggle this reviewer's key approver status
        reviewer.isKeyApprover.toggle()
        
        do {
            try modelContext.save()
            print("✅ Updated key approver status for \(reviewer.displayName): \(reviewer.isKeyApprover)")
            syncKeyApproverStatus(reviewer)
        } catch {
            print("❌ Error updating key approver status: \(error)")
        }
    }
    
    private func syncKeyApproverStatus(_ reviewer: Reviewer) {
        guard let firestoreId = project.firestoreId else {
            print("⚠️ Cannot sync key approver status - project has no firestoreId")
            return
        }
        
        Task {
            do {
                print("🔄 Syncing key approver status to Firestore for \(reviewer.displayName)")
                try await syncService.updateReviewerKeyApproverStatus(
                    projectId: firestoreId,
                    reviewerId: reviewer.id.uuidString,
                    isKeyApprover: reviewer.isKeyApprover
                )
                print("✅ Key approver status synced successfully")
            } catch {
                print("❌ Failed to sync key approver status: \(error.localizedDescription)")
            }
        }
    }
    
    private func removeReviewer(_ reviewer: Reviewer) {
        modelContext.delete(reviewer)
        
        do {
            try modelContext.save()
            print("✅ Removed reviewer locally: \(reviewer.displayName)")
            
            // Remove from Firestore
            if let firestoreId = project.firestoreId {
                Task {
                    do {
                        print("🔄 Removing reviewer from Firestore: \(reviewer.displayName)")
                        try await syncService.removeReviewer(
                            projectId: firestoreId,
                            reviewerId: reviewer.id.uuidString
                        )
                        print("✅ Reviewer removed from Firestore successfully")
                    } catch {
                        print("❌ Failed to remove reviewer from Firestore: \(error.localizedDescription)")
                        print("   Error details: \(error)")
                    }
                }
            } else {
                print("⚠️ Cannot remove from Firestore - project has no firestoreId")
            }
        } catch {
            print("❌ Error removing reviewer locally: \(error)")
        }
    }
}

struct ReviewerRow: View {
    let reviewer: Reviewer
    let isProducerView: Bool
    
    var statusIcon: String {
        switch reviewer.inviteStatus {
        case .notSent:
            return "envelope"
        case .sent:
            return "envelope.badge"
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .removed:
            return "minus.circle.fill"
        }
    }
    
    var statusColor: Color {
        switch reviewer.inviteStatus {
        case .notSent:
            return .gray
        case .sent:
            return .orange
        case .accepted:
            return .green
        case .declined:
            return .red
        case .removed:
            return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(reviewer.displayName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(reviewer.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if reviewer.role == .owner {
                        Text("Owner")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    
                    // Only show key approver badge to producers
                    if reviewer.isKeyApprover && isProducerView {
                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                            Text("Key Approver")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    }
                }
                
                Text(reviewer.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    Text(reviewer.inviteStatus.rawValue)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    
                    if reviewer.role != .owner {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reviewer.role.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let project = Project(
        name: "Test Project",
        clientName: "Test Client",
        ownerUserID: "user1"
    )
    
    let reviewer1 = Reviewer(
        displayName: "John Producer",
        email: "john@example.com",
        userId: "user1",
        role: .owner,
        inviteStatus: .accepted
    )
    reviewer1.project = project
    
    let reviewer2 = Reviewer(
        displayName: "Jane Artist",
        email: "jane@example.com",
        role: .reviewer,
        inviteStatus: .sent
    )
    reviewer2.project = project
    
    let reviewer3 = Reviewer(
        displayName: "Bob Client",
        email: "bob@example.com",
        userId: "user3",
        role: .viewer,
        inviteStatus: .accepted
    )
    reviewer3.project = project
    
    return ProjectReviewersView(project: project)
        .environment(AuthenticationService())
        .environment(ProjectSyncService(
            firestoreService: FirestoreService(),
            cloudStorageService: CloudStorageService(),
            authService: AuthenticationService()
        ))
        .modelContainer(for: Project.self, inMemory: true)
}

// MARK: - Edit Reviewer Sheet

struct EditReviewerSheet: View {
    @Bindable var reviewer: Reviewer
    let project: Project
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectSyncService.self) private var syncService
    
    @State private var editedDisplayName = ""
    @State private var editedEmail = ""
    @State private var editedRole: ReviewerRole = .reviewer
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                            ForEach([ReviewerRole.reviewer, .viewer], id: \.self) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Reviewer Details")
                }
            }
            .navigationTitle("Edit Reviewer")
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
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isSaving || editedDisplayName.isEmpty || editedEmail.isEmpty)
                }
            }
            .onAppear {
                editedDisplayName = reviewer.displayName
                editedEmail = reviewer.email
                editedRole = reviewer.role
            }
        }
    }
    
    private func saveChanges() async {
        isSaving = true
        
        // Normalize email
        let normalizedEmail = editedEmail.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Update local reviewer
        reviewer.displayName = editedDisplayName
        reviewer.email = normalizedEmail
        reviewer.role = editedRole
        
        do {
            try modelContext.save()
            print("✅ Updated reviewer locally: \(reviewer.displayName)")
            
            // Update in Firestore
            if let firestoreId = project.firestoreId {
                try await syncService.updateReviewer(
                    projectId: firestoreId,
                    reviewer: reviewer
                )
                print("✅ Reviewer updated in Firestore successfully")
            }
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        } catch {
            print("❌ Error updating reviewer: \(error)")
            await MainActor.run {
                isSaving = false
            }
        }
    }
}
