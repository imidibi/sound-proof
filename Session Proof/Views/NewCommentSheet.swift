//
//  NewCommentSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct NewCommentSheet: View {
    let mix: Mix
    let timestamp: TimeInterval
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var commentText = ""
    @State private var selectedTimestamp: TimeInterval
    @State private var endTimestamp: TimeInterval?
    @State private var useTimeRange = false
    @State private var voiceNoteRecorder = VoiceNoteRecorder()
    @State private var recordedVoiceNoteURL: URL?
    
    init(mix: Mix, timestamp: TimeInterval) {
        self.mix = mix
        self.timestamp = timestamp
        self._selectedTimestamp = State(initialValue: timestamp)
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
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $commentText)
                            .frame(height: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        
                        if commentText.isEmpty {
                            Text("Describe the issue or feedback at this timestamp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Comment")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    voiceNoteSection
                } header: {
                    HStack {
                        Text("Voice Note")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Comment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if voiceNoteRecorder.isRecording {
                            voiceNoteRecorder.cancelRecording()
                        }
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        createComment()
                    }
                    .disabled(commentText.isEmpty && recordedVoiceNoteURL == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }
    
    private var timestampCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                
                Text(formatTime(selectedTimestamp))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
            
            Toggle(isOn: $useTimeRange) {
                HStack {
                    Image(systemName: "arrow.left.and.right")
                        .foregroundStyle(.secondary)
                    Text("Mark time range")
                }
            }
            .toggleStyle(.switch)
            
            if useTimeRange {
                HStack {
                    Text("End time:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(endTimestamp ?? selectedTimestamp))
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
    private var voiceNoteSection: some View {
        if let url = recordedVoiceNoteURL {
            recordedVoiceNoteCard(url: url)
        } else if voiceNoteRecorder.isRecording {
            recordingCard
        } else {
            recordButton
        }
    }
    
    private var recordButton: some View {
        Button {
            voiceNoteRecorder.startRecording()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Record Voice Note")
                        .font(.headline)
                    Text("Tap to start recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private var recordingCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 16, height: 16)
                    
                    Circle()
                        .fill(.red)
                        .frame(width: 16, height: 16)
                        .opacity(0.5)
                        .scaleEffect(1.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceNoteRecorder.isRecording)
                }
                
                Text("Recording...")
                    .font(.headline)
                    .foregroundStyle(.red)
                
                Spacer()
                
                Text(formatTime(voiceNoteRecorder.recordingDuration))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            
            HStack(spacing: 12) {
                Button {
                    voiceNoteRecorder.cancelRecording()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                
                Button {
                    if let url = voiceNoteRecorder.stopRecording() {
                        recordedVoiceNoteURL = url
                    }
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
    
    private func recordedVoiceNoteCard(url: URL) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Note Recorded")
                    .font(.headline)
                
                Text("Ready to attach")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                recordedVoiceNoteURL = nil
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
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
    
    private func createComment() {
        let comment = Comment(
            timestamp: selectedTimestamp,
            endTimestamp: useTimeRange ? endTimestamp : nil,
            text: commentText,
            voiceNoteURL: recordedVoiceNoteURL,
            authorID: "current-user",
            authorName: "You"
        )
        
        comment.mix = mix
        if let song = mix.song {
            comment.song = song
        }
        
        modelContext.insert(comment)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating comment: \(error)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Mix.self, configurations: config)
    let context = container.mainContext
    
    let mix = Mix(name: "Mix V1", versionNumber: 1)
    context.insert(mix)
    
    return NewCommentSheet(mix: mix, timestamp: 45.0)
        .modelContainer(container)
}
