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
    
    @State private var projectName = ""
    @State private var clientName = ""
    @State private var notes = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $projectName)
                    TextField("Client Name (Optional)", text: $clientName)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
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
        .frame(minWidth: 400, minHeight: 350)
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
            clientName: clientName.isEmpty ? nil : clientName,
            ownerUserID: userId,
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(project)
        
        do {
            try modelContext.save()
            
            // Sync to cloud
            try await syncService.createAndSyncProject(
                project: project,
                modelContext: modelContext
            )
            
            await MainActor.run {
                isCreating = false
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
