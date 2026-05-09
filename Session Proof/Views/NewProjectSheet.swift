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
    
    @State private var projectName = ""
    @State private var clientName = ""
    @State private var notes = ""
    
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
                    Button("Create") {
                        createProject()
                    }
                    .disabled(projectName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }
    
    private func createProject() {
        let project = Project(
            name: projectName,
            clientName: clientName.isEmpty ? nil : clientName,
            ownerUserID: "current-user", // TODO: Replace with actual user ID
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(project)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating project: \(error)")
        }
    }
}

#Preview {
    NewProjectSheet()
        .modelContainer(for: Project.self, inMemory: true)
}
