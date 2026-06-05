//
//  NewProjectSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(ProjectSyncService.self) private var syncService
    
    @Query private var organizations: [Organization]
    
    var onProjectCreated: (() -> Void)? = nil
    
    // Basic Information
    @State private var projectName = ""
    @State private var artistName = ""
    @State private var producerName = ""
    @State private var studioName = ""
    @State private var genre = ""
    @State private var releaseDate: Date?
    @State private var showReleaseDatePicker = false
    
    // Workflow
    @State private var workflowStage: ProjectWorkflowStage = .tracking
    
    // Personnel
    @State private var assistantEngineer = ""
    @State private var masteringEngineer = ""
    
    // Label Contact
    @State private var labelContactName = ""
    @State private var labelContactEmail = ""
    @State private var labelContactPhone = ""
    
    // Manager
    @State private var managerName = ""
    @State private var managerEmail = ""
    @State private var managerPhone = ""
    
    // Legacy fields
    @State private var clientName = ""
    @State private var notes = ""
    
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    private var userOrganization: Organization? {
        guard let userId = authService.currentUser?.id else { return nil }
        return organizations.first { $0.memberIds.contains(userId) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $projectName)
                    TextField("Artist Name", text: $artistName)
                    TextField("Producer Name", text: $producerName)
                    TextField("Studio Name", text: $studioName)
                    TextField("Genre", text: $genre)
                    
                    Toggle("Set Release Date", isOn: $showReleaseDatePicker)
                    if showReleaseDatePicker {
                        DatePicker("Release Date", selection: Binding(
                            get: { releaseDate ?? Date() },
                            set: { releaseDate = $0 }
                        ), displayedComponents: .date)
                    }
                } header: {
                    Text("Basic Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Picker("Workflow Stage", selection: $workflowStage) {
                        Text("Tracking").tag(ProjectWorkflowStage.tracking)
                        Text("Editing").tag(ProjectWorkflowStage.editing)
                        Text("Mixing").tag(ProjectWorkflowStage.mixing)
                        Text("Mastering").tag(ProjectWorkflowStage.mastering)
                        Text("Review").tag(ProjectWorkflowStage.review)
                        Text("Approved").tag(ProjectWorkflowStage.approved)
                        Text("Released").tag(ProjectWorkflowStage.released)
                    }
                } header: {
                    Text("Workflow")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Assistant Engineer", text: $assistantEngineer)
                    TextField("Mastering Engineer", text: $masteringEngineer)
                } header: {
                    Text("Personnel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Name", text: $labelContactName)
                    TextField("Email", text: $labelContactEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        #endif
                    TextField("Phone", text: $labelContactPhone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        #endif
                } header: {
                    Text("Label Contact")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Name", text: $managerName)
                    TextField("Email", text: $managerEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        #endif
                    TextField("Phone", text: $managerPhone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        #endif
                } header: {
                    Text("Manager")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
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
                            await createProject()
                        }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(projectName.isEmpty || isCreating)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 700)
        #endif
    }
    
    private func createProject() async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "You must be signed in to create a project"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        let project = Project(
            name: projectName,
            artistName: artistName.isEmpty ? nil : artistName,
            producerName: producerName.isEmpty ? nil : producerName,
            studioName: studioName.isEmpty ? nil : studioName,
            genre: genre.isEmpty ? nil : genre,
            releaseDate: showReleaseDatePicker ? releaseDate : nil,
            clientName: clientName.isEmpty ? nil : clientName,
            ownerUserID: userId,
            organizationId: userOrganization?.id.uuidString,
            workflowStage: workflowStage,
            notes: notes.isEmpty ? nil : notes
        )
        
        // Set personnel
        project.assistantEngineerId = assistantEngineer.isEmpty ? nil : assistantEngineer
        project.masteringEngineerId = masteringEngineer.isEmpty ? nil : masteringEngineer
        
        // Set label contact
        project.labelContactName = labelContactName.isEmpty ? nil : labelContactName
        project.labelContactEmail = labelContactEmail.isEmpty ? nil : labelContactEmail
        project.labelContactPhone = labelContactPhone.isEmpty ? nil : labelContactPhone
        
        // Set manager
        project.managerName = managerName.isEmpty ? nil : managerName
        project.managerEmail = managerEmail.isEmpty ? nil : managerEmail
        project.managerPhone = managerPhone.isEmpty ? nil : managerPhone
        
        modelContext.insert(project)
        
        do {
            try modelContext.save()
            
            // Sync to cloud
            try await syncService.createAndSyncProject(
                project: project,
                modelContext: modelContext
            )
            
            // Ensure we're on main actor for dismiss
            await MainActor.run {
                isCreating = false
                // Call callback to close sheet
                onProjectCreated?()
                // Also call dismiss as fallback
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Error creating project: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}

#Preview {
    NewProjectSheet()
        .modelContainer(for: Project.self, inMemory: true)
}
