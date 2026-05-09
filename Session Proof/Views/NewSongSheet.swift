//
//  NewSongSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct NewSongSheet: View {
    let project: Project
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var songName = ""
    @State private var artist = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        
                        Text("Create New Song")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add a new song to \(project.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Song Name", systemImage: "music.note")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            TextField("e.g., Verse Chorus Bridge", text: $songName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Artist", systemImage: "person.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            
                            TextField("Optional", text: $artist)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Song Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Additional Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Song")
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
                        createSong()
                    }
                    .disabled(songName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }
    
    private func createSong() {
        let sortOrder = project.songs.count
        let song = Song(
            name: songName,
            artist: artist.isEmpty ? nil : artist,
            notes: notes.isEmpty ? nil : notes,
            sortOrder: sortOrder
        )
        
        song.project = project
        modelContext.insert(song)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating song: \(error)")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, configurations: config)
    let context = container.mainContext
    
    let project = Project(name: "Test Project", clientName: "Test Client", ownerUserID: "user1")
    context.insert(project)
    
    return NewSongSheet(project: project)
        .modelContainer(container)
}
