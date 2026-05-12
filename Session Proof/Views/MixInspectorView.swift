//
//  MixInspectorView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct MixInspectorView: View {
    @Bindable var mix: Mix
    let audioPlayerService: AudioPlayerService
    var onClose: (() -> Void)? = nil
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingNewCommentSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingNewCommentSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Add Comment")
                
                #if os(macOS)
                if let onClose = onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide Inspector (Cmd+I)")
                }
                #endif
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Song status
                    if let song = mix.song {
                        SongStatusSection(song: song)
                        Divider()
                    }
                    
                    // Mix info
                    MixInfoSection(mix: mix)
                    
                    Divider()
                    
                    // Comments
                    CommentsSection(mix: mix)
                    
                    Divider()
                    
                    // Approvals (if we have reviewers)
                    if let song = mix.song, let project = song.project {
                        ApprovalsSection(mix: mix, project: project)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingNewCommentSheet) {
            NewCommentSheet(
                mix: mix,
                timestamp: audioPlayerService.currentTime
            )
        }
    }
}

struct SongStatusSection: View {
    @Bindable var song: Song
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Song Status")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Picker("Status", selection: $song.status) {
                ForEach([SongStatus.inReview, .revisionsNeeded, .approved, .archived, .draft, .inProgress, .mixingComplete], id: \.self) { status in
                    Text("\(statusEmoji(for: status)) \(status.rawValue)")
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func statusEmoji(for status: SongStatus) -> String {
        switch status {
        case .inReview: return "👀"
        case .revisionsNeeded: return "⚠️"
        case .approved: return "✅"
        case .archived: return "📦"
        case .draft: return "📝"
        case .inProgress: return "🔄"
        case .mixingComplete: return "🎵"
        }
    }
}

struct SongStatusBadge: View {
    let status: SongStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusEmoji)
                .font(.caption)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .inReview: return .blue
        case .revisionsNeeded: return .orange
        case .approved: return .green
        case .archived: return .gray
        case .draft: return .gray
        case .inProgress: return .blue
        case .mixingComplete: return .green
        }
    }
    
    private var statusEmoji: String {
        switch status {
        case .inReview: return "🔵"
        case .revisionsNeeded: return "🟠"
        case .approved: return "✅"
        case .archived: return "⚫"
        case .draft: return "📝"
        case .inProgress: return "🔵"
        case .mixingComplete: return "🎵"
        }
    }
}

struct MixInfoSection: View {
    @Bindable var mix: Mix
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mix Status")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Picker("Status", selection: $mix.approvalStatus) {
                ForEach([MixStatus.draft, .shared, .inReview, .approved, .superseded], id: \.self) { status in
                    Text("\(mixStatusEmoji(for: status)) \(status.rawValue)")
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: mix.approvalStatus) { oldValue, newValue in
                if newValue == .approved {
                    markOtherMixesAsSuperseded()
                }
            }
            
            Divider()
            
            LabeledContent("Name", value: mix.name)
            LabeledContent("Version", value: "V\(mix.versionNumber)")
            
            Divider()
            
            // Format section
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    if let format = mix.format {
                        HStack {
                            Text("Type:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(format)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    
                    HStack {
                        Text("Duration:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(mix.duration))
                            .font(.caption)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    
                    if let bitrate = mix.bitrate {
                        HStack {
                            Text("Bitrate:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(bitrate) kbps")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    
                    HStack {
                        Text("Sample Rate:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSampleRate(mix.sampleRate))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Channels:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatChannels(mix.channels))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
            
            if let notes = mix.notes, !notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(notes)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func markOtherMixesAsSuperseded() {
        // When a mix is approved, mark all other mixes in the same song as superseded
        guard let song = mix.song else { return }
        
        for otherMix in song.mixes where otherMix.id != mix.id && otherMix.approvalStatus == .approved {
            otherMix.approvalStatus = .superseded
        }
    }
    
    private func mixStatusEmoji(for status: MixStatus) -> String {
        switch status {
        case .draft: return "📝"
        case .shared: return "📤"
        case .inReview: return "👀"
        case .approved: return "✅"
        case .superseded: return "⏭️"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatSampleRate(_ sampleRate: Double) -> String {
        let kHz = sampleRate / 1000.0
        return String(format: "%.1f kHz", kHz)
    }
    
    private func formatChannels(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels) channels"
        }
    }
}

struct CommentsSection: View {
    let mix: Mix
    
    var sortedComments: [Comment] {
        mix.comments.sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Comments")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(sortedComments.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if sortedComments.isEmpty {
                Text("No comments yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sortedComments) { comment in
                    CommentRowView(comment: comment)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommentRowView: View {
    let comment: Comment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatTimestamp(comment.timestamp))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                
                Spacer()
                
                CommentStatusIndicator(status: comment.status)
            }
            
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.caption)
            }
            
            if comment.voiceNoteURL != nil {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text("Voice note")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Text(comment.authorName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CommentStatusIndicator: View {
    let status: CommentStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch status {
        case .open: return .orange
        case .resolved: return .green
        case .rejected: return .red
        case .convertedToTask: return .blue
        }
    }
}

struct ApprovalsSection: View {
    let mix: Mix
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Approvals")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(mix.approvals.count)/\(project.reviewers.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if project.reviewers.isEmpty {
                Text("No reviewers assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(project.reviewers) { reviewer in
                    ApprovalRowView(
                        reviewer: reviewer,
                        approval: mix.approvals.first { $0.reviewer?.id == reviewer.id }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ApprovalRowView: View {
    let reviewer: Reviewer
    let approval: Approval?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reviewer.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let approval = approval {
                    Text(approval.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(approvalColor(approval.status))
                } else {
                    Text("Pending")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            ApprovalStatusIcon(status: approval?.status ?? .pending)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func approvalColor(_ status: ApprovalStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .approved: return .green
        case .changesRequested: return .orange
        }
    }
}

struct ApprovalStatusIcon: View {
    let status: ApprovalStatus
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .font(.caption)
    }
    
    private var iconName: String {
        switch status {
        case .pending: return "clock"
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "exclamationmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch status {
        case .pending: return .gray
        case .approved: return .green
        case .changesRequested: return .orange
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Mix.self, configurations: config)
    let context = container.mainContext
    
    let mix = Mix(name: "Mix V1", versionNumber: 1, duration: 180)
    context.insert(mix)
    
    return MixInspectorView(mix: mix, audioPlayerService: AudioPlayerService())
        .frame(width: 300)
        .modelContainer(container)
}
