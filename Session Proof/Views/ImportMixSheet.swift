//
//  ImportMixSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

struct ImportMixSheet: View {
    let song: Song
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSyncService.self) private var syncService
    @Environment(CloudStorageService.self) private var cloudStorage
    @Environment(AuthenticationService.self) private var authService
    
    @State private var mixName = ""
    @State private var notes = ""
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var uploadProgress: String?
    
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
                        TextField("Mix Name", text: $mixName, prompt: Text("e.g., Mix V1, Mastered"))
                            .textFieldStyle(.roundedBorder)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $notes)
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                #if os(iOS)
                                .background(Color(uiColor: .systemGray6))
                                #else
                                .background(Color(nsColor: .controlBackgroundColor))
                                #endif
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
                
                if let uploadProgress = uploadProgress {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(uploadProgress)
                                .font(.callout)
                        }
                    }
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
            .navigationTitle("Import Mix")
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
                            await importMix()
                        }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(mixName.isEmpty || selectedFileURL == nil || isImporting)
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
                let versionNumber = song.mixes.count + 1
                mixName = "Mix V\(versionNumber)"
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
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
    
    private func importMix() async {
        guard let sourceURL = selectedFileURL else { return }
        
        // Only project owners can create mixes
        guard let project = song.project, project.isOwner(userId: authService.currentUser?.id) else {
            await MainActor.run {
                errorMessage = "Only the project owner can create mixes"
                isImporting = false
            }
            return
        }
        
        isImporting = true
        errorMessage = nil
        
        do {
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
            let versionNumber = song.mixes.count + 1
            let mix = Mix(
                name: mixName,
                versionNumber: versionNumber,
                assetURL: destinationURL,
                assetFileName: fileName, // Store relative filename for persistence
                notes: notes.isEmpty ? nil : notes,
                lastModifiedAt: Date(),
                needsUpload: true  // Mark for automatic upload
            )
            
            // Load audio properties
            let asset = AVURLAsset(url: destinationURL)
            let duration = try await asset.load(.duration).seconds
            mix.duration = duration
            
            // Extract format from file extension
            let fileExtension = destinationURL.pathExtension.uppercased()
            mix.format = fileExtension.isEmpty ? "Unknown" : fileExtension
            
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let sampleRate = try await track.load(.naturalTimeScale)
                let formatDescriptions = try await track.load(.formatDescriptions)
                let estimatedDataRate = try await track.load(.estimatedDataRate)
                
                mix.sampleRate = Double(sampleRate)
                
                // Convert bitrate from bits per second to kilobits per second
                if estimatedDataRate > 0 {
                    mix.bitrate = Int(estimatedDataRate / 1000)
                }
                
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
            
            // Upload to cloud if project is synced
            if let project = song.project,
               let projectId = project.firestoreId,
               let songId = song.firestoreId {
                
                await MainActor.run {
                    uploadProgress = "Uploading to cloud..."
                }
                
                do {
                    try await syncService.uploadMix(
                        mix: mix,
                        projectId: projectId,
                        songId: songId,
                        modelContext: modelContext
                    )
                } catch {
                    // Don't fail the whole import if upload fails
                    print("Cloud upload failed: \(error)")
                    await MainActor.run {
                        uploadProgress = "Cloud upload failed (saved locally)"
                    }
                }
            }
            
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
    let container = try! ModelContainer(for: Song.self, configurations: config)
    let context = container.mainContext
    
    let song = Song(name: "Test Song")
    context.insert(song)
    
    return ImportMixSheet(song: song)
        .modelContainer(container)
}
