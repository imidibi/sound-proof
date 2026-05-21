//
//  CommentDetailSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/11/26.
//

import SwiftUI
import SwiftData
import AVFoundation

struct CommentDetailSheet: View {
    @Bindable var comment: Comment
    let onSeek: (TimeInterval) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(ProjectSyncService.self) private var syncService
    
    @State private var isEditing = false
    @State private var editedText: String
    @State private var showingDeleteConfirmation = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate: VoiceNotePlayerDelegate?
    @State private var isPlayingVoiceNote = false
    @State private var voiceNoteTimer: Timer?
    @State private var voiceNoteProgress: Double = 0
    @State private var isDownloadingVoiceNote = false
    
    init(comment: Comment, onSeek: @escaping (TimeInterval) -> Void) {
        self.comment = comment
        self.onSeek = onSeek
        self._editedText = State(initialValue: comment.text)
    }
    
    var canEdit: Bool {
        // Producers can edit/delete any comment
        // Users can edit/delete their own comments
        authService.currentUser?.role == .producer || 
        authService.currentUser?.id == comment.authorID
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    timestampCard
                } header: {
                    Text("Timestamp")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    commentContent
                } header: {
                    Text("Comment")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if comment.resolvedVoiceNoteURL != nil {
                    Section {
                        voiceNoteCard
                    } header: {
                        Text("Voice Note")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Author")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(comment.authorName)
                        }
                        .font(.subheadline)
                        
                        Divider()
                        
                        HStack {
                            Text("Created")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatDate(comment.createdAt))
                        }
                        .font(.subheadline)
                        
                        Divider()
                        
                        HStack {
                            Text("Status")
                                .foregroundStyle(.secondary)
                            Spacer()
                            CommentStatusIndicator(status: comment.status)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if canEdit {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Comment", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Comment" : "Comment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Close") {
                        if isEditing {
                            editedText = comment.text
                            isEditing = false
                        } else {
                            stopVoiceNote()
                            dismiss()
                        }
                    }
                }
                
                if canEdit && !isEditing {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                } else if isEditing {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Save") {
                            saveChanges()
                        }
                        .disabled(editedText.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                "Delete Comment",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteComment()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this comment? This action cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .onDisappear {
            stopVoiceNote()
        }
    }
    
    private var timestampCard: some View {
        VStack(spacing: 12) {
            Button {
                onSeek(comment.timestamp)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    
                    Text(formatTime(comment.timestamp))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            if let endTimestamp = comment.endTimestamp {
                HStack {
                    Image(systemName: "arrow.left.and.right")
                        .foregroundStyle(.secondary)
                    Text("End time:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(endTimestamp))
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var commentContent: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $editedText)
                    .frame(height: 120)
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
                
                if editedText.isEmpty {
                    Text("Comment text is required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        } else {
            if comment.text.isEmpty {
                Text("No comment text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Text(comment.text)
                    .font(.subheadline)
                    .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private var voiceNoteCard: some View {
        if comment.voiceNoteURL != nil || comment.voiceNoteFileName != nil {
            // Show voice note UI even if file doesn't exist locally yet
            voiceNoteCardContent
        }
    }
    
    @ViewBuilder
    private var voiceNoteCardContent: some View {
        if let url = comment.resolvedVoiceNoteURL,
           FileManager.default.fileExists(atPath: url.path) {
            // File exists locally - show playback controls
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button {
                        if isPlayingVoiceNote {
                            pauseVoiceNote()
                        } else {
                            playVoiceNote(url: url)
                        }
                    } label: {
                        Image(systemName: isPlayingVoiceNote ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice Note")
                            .font(.headline)
                        
                        if let player = audioPlayer {
                            Text(formatVoiceNoteTime(player.currentTime, duration: player.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text("Tap to play")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                if let player = audioPlayer, player.duration > 0 {
                    ProgressView(value: voiceNoteProgress)
                        .tint(.green)
                }
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: isPlayingVoiceNote ? 2 : 1)
            )
        } else {
            // Voice note file doesn't exist locally
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if isDownloadingVoiceNote {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isDownloadingVoiceNote ? "Downloading..." : "Voice Note Unavailable")
                            .font(.headline)
                        
                        Text(isDownloadingVoiceNote ? "Fetching from cloud" : "File not found locally")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Show download button if we have a cloud URL
                    if !isDownloadingVoiceNote, comment.voiceNoteCloudURL != nil {
                        Button {
                            Task {
                                await downloadVoiceNote()
                            }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func playVoiceNote(url: URL) {
        // Debug: Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("🎵 Attempting to play voice note:")
        print("   URL: \(url)")
        print("   Path: \(url.path)")
        print("   File exists: \(fileExists)")
        
        if !fileExists {
            print("❌ Voice note file does not exist at path")
            return
        }
        
        // Check file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            print("   File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("❌ Voice note file is empty (0 bytes)")
                return
            }
        }
        
        do {
            // Configure audio session for playback on iOS
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            #endif
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            
            let delegate = VoiceNotePlayerDelegate(onFinish: {
                isPlayingVoiceNote = false
                voiceNoteProgress = 0
                voiceNoteTimer?.invalidate()
                voiceNoteTimer = nil
            })
            audioPlayerDelegate = delegate
            audioPlayer?.delegate = delegate
            
            print("✅ Audio player created, duration: \(audioPlayer?.duration ?? 0)s")
            
            let playSuccess = audioPlayer?.play() ?? false
            print("   Play initiated: \(playSuccess)")
            
            if playSuccess {
                isPlayingVoiceNote = true
                
                // Start progress timer
                voiceNoteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let player = audioPlayer, player.duration > 0 {
                        voiceNoteProgress = player.currentTime / player.duration
                    }
                }
            } else {
                print("❌ AVAudioPlayer.play() returned false")
            }
        } catch {
            print("❌ Error creating/playing voice note:")
            print("   Error: \(error)")
            print("   Error code: \((error as NSError).code)")
            print("   Error domain: \((error as NSError).domain)")
        }
    }
    
    private func pauseVoiceNote() {
        audioPlayer?.pause()
        isPlayingVoiceNote = false
        voiceNoteTimer?.invalidate()
        voiceNoteTimer = nil
    }
    
    private func stopVoiceNote() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingVoiceNote = false
        voiceNoteProgress = 0
        voiceNoteTimer?.invalidate()
        voiceNoteTimer = nil
    }
    
    private func downloadVoiceNote() async {
        isDownloadingVoiceNote = true
        
        let success = await syncService.downloadMissingVoiceNote(for: comment)
        
        await MainActor.run {
            isDownloadingVoiceNote = false
            
            if success {
                print("✅ Voice note successfully re-downloaded")
                // Trigger view update by checking the file exists
                if let url = comment.resolvedVoiceNoteURL,
                   FileManager.default.fileExists(atPath: url.path) {
                    print("✅ Voice note now available for playback")
                }
            } else {
                print("❌ Failed to download voice note")
            }
        }
    }
    
    private func saveChanges() {
        comment.text = editedText
        
        do {
            try modelContext.save()
            isEditing = false
        } catch {
            print("Error saving comment: \(error)")
        }
    }
    
    private func deleteComment() {
        stopVoiceNote()
        modelContext.delete(comment)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error deleting comment: \(error)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    private func formatVoiceNoteTime(_ current: TimeInterval, duration: TimeInterval) -> String {
        let currentMin = Int(current) / 60
        let currentSec = Int(current) % 60
        let durationMin = Int(duration) / 60
        let durationSec = Int(duration) % 60
        return String(format: "%d:%02d / %d:%02d", currentMin, currentSec, durationMin, durationSec)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Helper delegate for AVAudioPlayer
private class VoiceNotePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Comment.self, configurations: config)
    let context = container.mainContext
    
    let comment = Comment(
        timestamp: 45.67,
        text: "The guitar is too loud in this section",
        authorID: "user1",
        authorName: "John Producer"
    )
    context.insert(comment)
    
    return CommentDetailSheet(comment: comment, onSeek: { _ in })
        .modelContainer(container)
}
