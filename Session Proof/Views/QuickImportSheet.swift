//
//  QuickImportSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

struct QuickImportSheet: View {
    let project: Project
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var songName = ""
    @State private var artist = ""
    @State private var mixName = ""
    @State private var notes = ""
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = selectedFileURL {
                        audioFileCard(url: url)
                    } else {
                        selectFileButton
                    }
                } header: {
                    Text("Audio File")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Song Name", text: $songName, prompt: Text("e.g., Track 01, Song Title"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: selectedFileURL) { _, newValue in
                                if songName.isEmpty, let url = newValue {
                                    songName = url.deletingPathExtension().lastPathComponent
                                }
                            }
                        
                        TextField("Artist", text: $artist, prompt: Text("Optional"))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Song Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Mix Name", text: $mixName, prompt: Text("e.g., Mix V1"))
                            .textFieldStyle(.roundedBorder)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $notes)
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Mix Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await importAudio()
                        }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(songName.isEmpty || mixName.isEmpty || selectedFileURL == nil || isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    selectedFileURL = urls.first
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onAppear {
                mixName = "Mix V1"
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 550)
        #endif
    }
    
    private var selectFileButton: some View {
        Button {
            showingFilePicker = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                
                Text("Select Audio File")
                    .font(.headline)
                
                Text("Supports WAV, AIFF, MP3, M4A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func audioFileCard(url: URL) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(2)
                
                Text("Ready to import")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Change") {
                showingFilePicker = true
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
        )
    }
    
    private func importAudio() async {
        guard let sourceURL = selectedFileURL else { return }
        
        isImporting = true
        errorMessage = nil
        
        do {
            // Create the song
            let sortOrder = project.songs.count
            let song = Song(
                name: songName,
                artist: artist.isEmpty ? nil : artist,
                sortOrder: sortOrder
            )
            song.project = project
            modelContext.insert(song)
            
            // Copy file to app's documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = sourceURL.lastPathComponent
            let destinationURL = documentsPath.appendingPathComponent(fileName)
            
            // Start accessing security-scoped resource
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Create mix with relative filename
            let mix = Mix(
                name: mixName,
                versionNumber: 1,
                assetURL: destinationURL,
                assetFileName: fileName, // Store relative filename for persistence
                notes: notes.isEmpty ? nil : notes
            )
            
            // Load audio properties
            let asset = AVURLAsset(url: destinationURL)
            let duration = try await asset.load(.duration).seconds
            mix.duration = duration
            
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let sampleRate = try await track.load(.naturalTimeScale)
                let formatDescriptions = try await track.load(.formatDescriptions)
                
                mix.sampleRate = Double(sampleRate)
                
                if let formatDescription = formatDescriptions.first {
                    let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
                    if let description = audioStreamBasicDescription {
                        mix.channels = Int(description.pointee.mChannelsPerFrame)
                    }
                }
            }
            
            mix.song = song
            modelContext.insert(mix)
            
            try modelContext.save()
            
            await MainActor.run {
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Error importing audio: \(error.localizedDescription)"
                isImporting = false
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, configurations: config)
    let context = container.mainContext
    
    let project = Project(name: "Test Project", clientName: "Test Client", ownerUserID: "user1")
    context.insert(project)
    
    return QuickImportSheet(project: project)
        .modelContainer(container)
}
