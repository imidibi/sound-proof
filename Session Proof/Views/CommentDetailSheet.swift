//
//  CommentDetailSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/11/26.
//

import SwiftUI
import SwiftData

struct CommentDetailSheet: View {
    @Bindable var comment: Comment
    let onSeek: (TimeInterval) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    
    @State private var isEditing = false
    @State private var editedText: String
    @State private var showingDeleteConfirmation = false
    
    init(comment: Comment, onSeek: @escaping (TimeInterval) -> Void) {
        self.comment = comment
        self.onSeek = onSeek
        self._editedText = State(initialValue: comment.text)
    }
    
    var canEdit: Bool {
        authService.currentUser?.role == .producer
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Timestamp") {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                        
                        Text(formatTime(comment.timestamp))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Button {
                            onSeek(comment.timestamp)
                        } label: {
                            Label("Jump to Time", systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                    
                    if let endTimestamp = comment.endTimestamp {
                        HStack {
                            Image(systemName: "arrow.left.and.right")
                                .foregroundStyle(.secondary)
                            Text("End: \(formatTime(endTimestamp))")
                                .monospacedDigit()
                        }
                    }
                }
                
                Section("Comment") {
                    if isEditing {
                        TextEditor(text: $editedText)
                            .frame(minHeight: 120)
                    } else {
                        Text(comment.text.isEmpty ? "No text" : comment.text)
                            .foregroundStyle(comment.text.isEmpty ? .secondary : .primary)
                    }
                }
                
                if comment.voiceNoteURL != nil {
                    Section("Voice Note") {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice Note Attached")
                                    .font(.headline)
                                Text("Tap to play")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Details") {
                    LabeledContent("Author", value: comment.authorName)
                    LabeledContent("Created", value: formatDate(comment.createdAt))
                    LabeledContent("Status", value: comment.status.rawValue)
                }
                
                if canEdit {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Comment", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Comment Details")
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
                            dismiss()
                        }
                    }
                }
                
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        if isEditing {
                            Button("Save") {
                                saveChanges()
                            }
                            .disabled(editedText.isEmpty)
                        } else {
                            Button("Edit") {
                                isEditing = true
                            }
                        }
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
        .frame(minWidth: 500, minHeight: 400)
        #endif
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
