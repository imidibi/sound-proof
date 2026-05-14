//
//  ProjectEditSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/14/26.
//

import SwiftUI
import SwiftData

struct ProjectEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @Bindable var project: Project
    
    @Query private var organizations: [Organization]
    
    @State private var showReleaseDatePicker = false
    @State private var errorMessage: String?
    
    private var userOrganization: Organization? {
        guard let userId = authService.currentUser?.id else { return nil }
        return organizations.first { $0.memberIds.contains(userId) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $project.name)
                    TextField("Artist Name", text: Binding(
                        get: { project.artistName ?? "" },
                        set: { project.artistName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Producer Name", text: Binding(
                        get: { project.producerName ?? "" },
                        set: { project.producerName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Studio Name", text: Binding(
                        get: { project.studioName ?? "" },
                        set: { project.studioName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Genre", text: Binding(
                        get: { project.genre ?? "" },
                        set: { project.genre = $0.isEmpty ? nil : $0 }
                    ))
                    
                    Toggle("Has Release Date", isOn: Binding(
                        get: { project.releaseDate != nil },
                        set: { hasDate in
                            if hasDate && project.releaseDate == nil {
                                project.releaseDate = Date()
                            } else if !hasDate {
                                project.releaseDate = nil
                            }
                        }
                    ))
                    
                    if project.releaseDate != nil {
                        DatePicker("Release Date", selection: Binding(
                            get: { project.releaseDate ?? Date() },
                            set: { project.releaseDate = $0 }
                        ), displayedComponents: .date)
                    }
                } header: {
                    Text("Basic Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Picker("Workflow Stage", selection: Binding(
                        get: { project.workflowStage ?? .tracking },
                        set: { project.workflowStage = $0 }
                    )) {
                        Text("Tracking").tag(ProjectWorkflowStage.tracking)
                        Text("Editing").tag(ProjectWorkflowStage.editing)
                        Text("Mixing").tag(ProjectWorkflowStage.mixing)
                        Text("Mastering").tag(ProjectWorkflowStage.mastering)
                        Text("Review").tag(ProjectWorkflowStage.review)
                        Text("Approved").tag(ProjectWorkflowStage.approved)
                        Text("Released").tag(ProjectWorkflowStage.released)
                        Text("Archived").tag(ProjectWorkflowStage.archived)
                    }
                } header: {
                    Text("Workflow")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Assistant Engineer", text: Binding(
                        get: { project.assistantEngineerId ?? "" },
                        set: { project.assistantEngineerId = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Mastering Engineer", text: Binding(
                        get: { project.masteringEngineerId ?? "" },
                        set: { project.masteringEngineerId = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Personnel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Name", text: Binding(
                        get: { project.labelContactName ?? "" },
                        set: { project.labelContactName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Email", text: Binding(
                        get: { project.labelContactEmail ?? "" },
                        set: { project.labelContactEmail = $0.isEmpty ? nil : $0 }
                    ))
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    #endif
                    TextField("Phone", text: Binding(
                        get: { project.labelContactPhone ?? "" },
                        set: { project.labelContactPhone = $0.isEmpty ? nil : $0 }
                    ))
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
                    TextField("Name", text: Binding(
                        get: { project.managerName ?? "" },
                        set: { project.managerName = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Email", text: Binding(
                        get: { project.managerEmail ?? "" },
                        set: { project.managerEmail = $0.isEmpty ? nil : $0 }
                    ))
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    #endif
                    TextField("Phone", text: Binding(
                        get: { project.managerPhone ?? "" },
                        set: { project.managerPhone = $0.isEmpty ? nil : $0 }
                    ))
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
                    TextEditor(text: Binding(
                        get: { project.notes ?? "" },
                        set: { project.notes = $0.isEmpty ? nil : $0 }
                    ))
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
            .navigationTitle("Edit Project")
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
                        saveProject()
                    }
                    .disabled(project.name.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 700)
        #endif
    }
    
    private func saveProject() {
        project.updatedAt = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Error saving project: \(error.localizedDescription)"
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, configurations: config)
    let context = container.mainContext
    
    let project = Project(name: "Test Project", ownerUserID: "user1")
    context.insert(project)
    
    return ProjectEditSheet(project: project)
        .modelContainer(container)
}
