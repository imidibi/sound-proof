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
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCommentSheet = false
    @State private var showingCancelConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                #if os(iOS)
                Button("Cancel") {
                    handleCancel()
                }
                .foregroundStyle(.red)
                
                Spacer()
                #endif
                
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
                Button {
                    handleCancel()
                } label: {
                    Text("Cancel")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Discard Changes")
                
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
                            .id(mix.approvals.count) // Force refresh when approval count changes
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
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                discardChanges()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Any unsaved changes will be lost.")
        }
    }
    
    private func handleCancel() {
        #if os(iOS)
        showingCancelConfirmation = true
        #elseif os(macOS)
        showingCancelConfirmation = true
        #endif
    }
    
    private func discardChanges() {
        // Rollback any changes made to the model context
        modelContext.rollback()
        
        #if os(iOS)
        dismiss()
        #elseif os(macOS)
        if let onClose = onClose {
            onClose()
        }
        #endif
    }
}

struct SongStatusSection: View {
    @Bindable var song: Song
    @Environment(AuthenticationService.self) private var authService
    
    // Check if current user is the producer
    var isProducer: Bool {
        guard let project = song.project,
              let currentUserId = authService.currentUser?.id else {
            return false
        }
        return currentUserId == project.ownerUserID
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Song Status")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if isProducer {
                // Producer can edit song status
                if song.status == .approved {
                    HStack(spacing: 8) {
                        Text("\(statusEmoji(for: song.status)) \(song.status.rawValue)")
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Text("Approved by key approver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                } else {
                    // Allow changing status for non-approved songs (exclude .approved from options)
                    Picker("Status", selection: $song.status) {
                        ForEach([SongStatus.inReview, .revisionsNeeded, .archived, .draft, .inProgress, .mixingComplete], id: \.self) { status in
                            Text("\(statusEmoji(for: status)) \(status.rawValue)")
                                .tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                // Non-producers see read-only status
                HStack(spacing: 8) {
                    Text("\(statusEmoji(for: song.status)) \(song.status.rawValue)")
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor(for: song.status).opacity(0.2))
                        .foregroundStyle(statusColor(for: song.status))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func statusEmoji(for status: SongStatus) -> String {
        switch status {
        case .inReview: return "👀"
        case .shared: return "📤"
        case .revisionsNeeded: return "⚠️"
        case .approved: return "✅"
        case .archived: return "📦"
        case .draft: return "📝"
        case .inProgress: return "🔄"
        case .mixingComplete: return "🎵"
        }
    }
    
    private func statusColor(for status: SongStatus) -> Color {
        switch status {
        case .inReview: return .blue
        case .shared: return .cyan
        case .revisionsNeeded: return .orange
        case .approved: return .green
        case .archived: return .gray
        case .draft: return .secondary
        case .inProgress: return .blue
        case .mixingComplete: return .purple
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
        case .shared: return .cyan
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
        case .shared: return "📤"
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
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(AuthenticationService.self) private var authService
    
    // Check if current user can approve mixes (producer or key approver)
    var canApproveMix: Bool {
        guard let currentUserId = authService.currentUser?.id,
              let project = mix.song?.project else {
            return false
        }
        
        let isProducer = authService.currentUser?.isProducer ?? false
        let isKeyApprover = project.reviewers.first(where: { $0.userId == currentUserId })?.isKeyApprover ?? false
        
        return isProducer || isKeyApprover
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mix Status")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Picker("Status", selection: $mix.approvalStatus) {
                // Show all statuses to producers/key approvers
                // Artists can only see non-approval statuses
                if canApproveMix {
                    ForEach([MixStatus.draft, .shared, .inReview, .approved, .superseded], id: \.self) { status in
                        Text("\(mixStatusEmoji(for: status)) \(status.rawValue)")
                            .tag(status)
                    }
                } else {
                    // Artists cannot set mix to approved
                    ForEach([MixStatus.draft, .shared, .inReview, .superseded], id: \.self) { status in
                        Text("\(mixStatusEmoji(for: status)) \(status.rawValue)")
                            .tag(status)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(!canApproveMix && mix.approvalStatus == .approved) // Don't let artists change approved status
            .onChange(of: mix.approvalStatus) { oldValue, newValue in
                Task {
                    await handleApprovalStatusChange(from: oldValue, to: newValue)
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
        guard let song = mix.song,
              let project = song.project,
              let projectId = project.firestoreId,
              let songId = song.firestoreId else { return }
        
        for otherMix in song.mixes where otherMix.id != mix.id && otherMix.approvalStatus == .approved {
            otherMix.approvalStatus = .superseded
            
            // Sync this status change to Firestore as well
            if let mixId = otherMix.firestoreId {
                Task {
                    do {
                        try await firestoreService.updateMixStatus(
                            projectId: projectId,
                            songId: songId,
                            mixId: mixId,
                            status: .superseded
                        )
                        print("✅ Marked mix '\(otherMix.name)' as superseded in Firestore")
                    } catch {
                        print("❌ Failed to sync superseded status for mix '\(otherMix.name)': \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func handleApprovalStatusChange(from oldStatus: MixStatus, to newStatus: MixStatus) async {
        guard let song = mix.song,
              let project = song.project else {
            print("⚠️ Cannot handle approval - missing song or project")
            return
        }
        
        // Sync the status change to Firestore
        await syncMixStatus()
        
        // If the status is being set to approved, create/update an Approval record
        if newStatus == .approved, let currentUserId = authService.currentUser?.id {
            await createOrUpdateApproval(userId: currentUserId, project: project)
            
            // Check if current user is key approver or producer
            let isKeyApprover = project.reviewers.first(where: { $0.userId == currentUserId })?.isKeyApprover ?? false
            let isProducer = authService.currentUser?.isProducer ?? false
            
            print("📋 Approval context:")
            print("   User ID: \(currentUserId)")
            print("   Is Key Approver: \(isKeyApprover)")
            print("   Is Producer: \(isProducer)")
            
            // If user is key approver or producer, approve the song and supersede other mixes
            if isKeyApprover || isProducer {
                print("👑 Key approver or producer approved mix - approving song and superseding others")
                
                // Approve the song
                song.status = .approved
                
                // Mark other mixes as superseded
                markOtherMixesAsSuperseded()
                
                // Save changes
                do {
                    try modelContext.save()
                    print("✅ Song approved and other mixes superseded")
                } catch {
                    print("❌ Error saving approval changes: \(error)")
                }
            } else {
                print("ℹ️ Regular reviewer approved mix - recording opinion only")
            }
        }
    }
    
    private func createOrUpdateApproval(userId: String, project: Project) async {
        print("🔍 createOrUpdateApproval called")
        print("   User ID: \(userId)")
        print("   Project reviewers count: \(project.reviewers.count)")
        
        for rev in project.reviewers {
            print("   Reviewer: \(rev.displayName), userId: \(rev.userId ?? "nil"), id: \(rev.id)")
        }
        
        // Find the reviewer for this user
        guard let reviewer = project.reviewers.first(where: { $0.userId == userId }) else {
            print("⚠️ Cannot create approval - reviewer not found for user ID: \(userId)")
            return
        }
        
        print("✅ Found reviewer: \(reviewer.displayName) (id: \(reviewer.id))")
        print("   Current approvals for mix: \(mix.approvals.count)")
        
        // Check if an approval already exists for this reviewer and mix
        let existingApproval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id })
        
        if let approval = existingApproval {
            // Update existing approval
            approval.status = .approved
            approval.updatedAt = Date()
            print("✅ Updated existing approval for \(reviewer.displayName)")
        } else {
            // Create new approval
            let approval = Approval(status: .approved)
            approval.mix = mix
            approval.reviewer = reviewer
            modelContext.insert(approval)
            print("✅ Created new approval for \(reviewer.displayName)")
            print("   Approval ID: \(approval.id)")
            print("   Linked to reviewer ID: \(approval.reviewer?.id ?? UUID())")
            print("   Linked to mix ID: \(approval.mix?.id ?? UUID())")
        }
        
        do {
            try modelContext.save()
            print("✅ Approval saved successfully")
            print("   Mix now has \(mix.approvals.count) approvals")
        } catch {
            print("❌ Error saving approval: \(error)")
        }
    }
    
    private func syncMixStatus() async {
        guard let song = mix.song,
              let project = song.project,
              let projectId = project.firestoreId,
              let songId = song.firestoreId,
              let mixId = mix.firestoreId else {
            print("⚠️ Cannot sync mix status - missing required IDs")
            print("   Mix ID: \(mix.id)")
            print("   Mix Firestore ID: \(mix.firestoreId ?? "nil")")
            print("   Song: \(mix.song?.name ?? "nil")")
            print("   Song Firestore ID: \(mix.song?.firestoreId ?? "nil")")
            print("   Project: \(mix.song?.project?.name ?? "nil")")
            print("   Project Firestore ID: \(mix.song?.project?.firestoreId ?? "nil")")
            return
        }
        
        do {
            print("🔄 Syncing mix status change to Firestore")
            print("   Mix: \(mix.name)")
            print("   Status: \(mix.approvalStatus.rawValue)")
            print("   Project ID: \(projectId)")
            print("   Song ID: \(songId)")
            print("   Mix ID: \(mixId)")
            
            try await firestoreService.updateMixStatus(
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                status: mix.approvalStatus
            )
            print("✅ Mix status synced successfully to Firestore")
        } catch {
            print("❌ Failed to sync mix status: \(error.localizedDescription)")
            print("   Error details: \(error)")
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
                
                // Sync status badge
                if comment.needsSync {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.caption2)
                        Text("Syncing")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
                
                Spacer()
                
                CommentStatusIndicator(status: comment.status)
            }
            
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.caption)
            }
            
            if comment.resolvedVoiceNoteURL != nil {
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
    @Bindable var mix: Mix
    let project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Query private var allApprovals: [Approval]
    
    // Computed property to get fresh approval data by querying all approvals
    private var approvalsByReviewer: [UUID: Approval] {
        // Find approvals for this specific mix from the full query
        let mixApprovals = allApprovals.filter { approval in
            approval.mix?.id == mix.id
        }
        
        var dict: [UUID: Approval] = [:]
        for approval in mixApprovals {
            if let reviewerId = approval.reviewer?.id {
                dict[reviewerId] = approval
            }
        }
        
        print("🔍 ApprovalsSection - Found \(dict.count) approvals for mix '\(mix.name)'")
        for (reviewerId, approval) in dict {
            print("   Reviewer ID: \(reviewerId), Status: \(approval.status.rawValue)")
        }
        
        return dict
    }
    
    // Get approval for producer (by userId, not reviewer record)
    private var producerApproval: Approval? {
        allApprovals.first { approval in
            approval.mix?.id == mix.id && approval.reviewer?.userId == project.ownerUserID
        }
    }
    
    // Check if producer is already in reviewers list
    private var producerInReviewers: Bool {
        project.reviewers.contains { $0.userId == project.ownerUserID }
    }
    
    // Total count including producer if not in reviewers
    private var totalReviewerCount: Int {
        producerInReviewers ? project.reviewers.count : project.reviewers.count + 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Approvals")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(mix.approvals.count)/\(totalReviewerCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Show producer first if not already in reviewers
            if !producerInReviewers {
                ProducerApprovalRowView(
                    mix: mix,
                    project: project,
                    approval: producerApproval
                )
            }
            
            // Show all reviewers
            if project.reviewers.isEmpty && producerInReviewers {
                Text("No reviewers assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(project.reviewers) { reviewer in
                    ApprovalRowView(
                        reviewer: reviewer,
                        mix: mix,
                        approval: approvalsByReviewer[reviewer.id]
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProducerApprovalRowView: View {
    @Bindable var mix: Mix
    let project: Project
    let approval: Approval?
    
    @Environment(AuthenticationService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(\.modelContext) private var modelContext
    
    // Check if this is the current user (producer)
    var isCurrentUser: Bool {
        guard let currentUserId = authService.currentUser?.id else {
            return false
        }
        return currentUserId == project.ownerUserID
    }
    
    // Get producer's display name from auth service or project
    var producerDisplayName: String {
        if let currentUser = authService.currentUser, currentUser.id == project.ownerUserID {
            return currentUser.displayName + " (Producer)"
        }
        return project.producerName ?? "Producer"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(producerDisplayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                
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
            
            // Show approval actions for producer
            if isCurrentUser {
                HStack(spacing: 8) {
                    // Show current status if already approved/requested changes
                    if let approval = approval, approval.status != .pending {
                        ApprovalStatusIcon(status: approval.status)
                    }
                    
                    // Always show buttons for current user to change their mind
                    Menu {
                        Button {
                            setApprovalStatus(.approved)
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                        }
                        
                        Button {
                            setApprovalStatus(.changesRequested)
                        } label: {
                            Label("Request Changes", systemImage: "exclamationmark.circle.fill")
                        }
                        
                        if approval?.status != .pending {
                            Button {
                                setApprovalStatus(.pending)
                            } label: {
                                Label("Reset to Pending", systemImage: "clock")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ApprovalStatusIcon(status: approval?.status ?? .pending)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func setApprovalStatus(_ status: ApprovalStatus) {
        print("🎯 Setting producer approval status to: \(status.rawValue)")
        print("   Producer: \(producerDisplayName)")
        print("   Mix: \(mix.name)")
        
        // We need to create or get a virtual reviewer for the producer
        // Find or create a reviewer record for the producer
        let producerReviewer: Reviewer
        if let existing = project.reviewers.first(where: { $0.userId == project.ownerUserID }) {
            producerReviewer = existing
        } else {
            // Create a virtual reviewer for the producer
            producerReviewer = Reviewer(
                displayName: producerDisplayName,
                email: authService.currentUser?.email ?? "",
                userId: project.ownerUserID,
                role: .owner,
                inviteStatus: .accepted,
                isKeyApprover: true
            )
            producerReviewer.project = project
            modelContext.insert(producerReviewer)
        }
        
        // Enforce one approval per user per song
        // If approving a mix, clear any other approvals by this user on other mixes of the same song
        if status == .approved, let song = mix.song {
            clearOtherMixApprovals(for: producerReviewer, in: song)
        }
        
        let approvalToSync: Approval
        
        if let existingApproval = approval {
            // Update existing approval
            existingApproval.status = status
            existingApproval.updatedAt = Date()
            existingApproval.needsUpload = true // Mark for sync
            approvalToSync = existingApproval
            print("✅ Updated existing producer approval")
        } else {
            // Create new approval
            let newApproval = Approval(status: status, needsUpload: true)
            newApproval.mix = mix
            newApproval.reviewer = producerReviewer
            modelContext.insert(newApproval)
            approvalToSync = newApproval
            print("✅ Created new producer approval")
        }
        
        do {
            try modelContext.save()
            print("✅ Saved producer approval to SwiftData")
            
            // Check if song should be auto-approved (producer is always a key approver)
            if status == .approved {
                checkAndAutoApproveSong()
            }
            
            // Sync to Firestore
            Task {
                await syncApprovalToFirestore(approvalToSync, reviewer: producerReviewer)
            }
        } catch {
            print("❌ Error saving producer approval: \(error)")
        }
    }
    
    private func syncApprovalToFirestore(_ approval: Approval, reviewer: Reviewer) async {
        guard let projectId = mix.song?.project?.firestoreId,
              let songId = mix.song?.firestoreId,
              let mixId = mix.firestoreId,
              let reviewerUserId = reviewer.userId else {
            print("❌ Missing IDs for Firestore sync")
            return
        }
        
        print("📤 Syncing producer approval to Firestore...")
        print("   Project ID: \(projectId)")
        print("   Song ID: \(songId)")
        print("   Mix ID: \(mixId)")
        print("   Reviewer User ID: \(reviewerUserId)")
        print("   Status: \(approval.status.rawValue)")
        
        do {
            _ = try await firestoreService.createOrUpdateApproval(
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                approval: approval,
                reviewerUserId: reviewerUserId
            )
            
            // Mark as synced
            await MainActor.run {
                approval.needsUpload = false
                approval.lastSyncedAt = Date()
                try? modelContext.save()
            }
            
            print("✅ Producer approval synced to Firestore")
        } catch {
            print("❌ Failed to sync producer approval: \(error.localizedDescription)")
        }
    }
    
    private func clearOtherMixApprovals(for reviewer: Reviewer, in song: Song) {
        // Find all approvals by this reviewer on other mixes in the same song
        for otherMix in song.mixes where otherMix.id != mix.id {
            if let otherApproval = otherMix.approvals.first(where: { $0.reviewer?.id == reviewer.id }) {
                if otherApproval.status == .approved {
                    print("🔄 Clearing previous approval on mix: \(otherMix.name)")
                    otherApproval.status = .pending
                    otherApproval.updatedAt = Date()
                    
                    // Sync to Firestore
                    if let projectId = project.firestoreId,
                       let songId = song.firestoreId,
                       let mixId = otherMix.firestoreId,
                       let reviewerUserId = reviewer.userId {
                        Task {
                            do {
                                _ = try await firestoreService.createOrUpdateApproval(
                                    projectId: projectId,
                                    songId: songId,
                                    mixId: mixId,
                                    approval: otherApproval,
                                    reviewerUserId: reviewerUserId
                                )
                                print("✅ Cleared approval synced to Firestore")
                            } catch {
                                print("❌ Failed to sync cleared approval: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func checkAndAutoApproveSong() {
        guard let song = mix.song else { return }
        
        // Producer is always a key approver, so auto-approve the song
        print("🎯 Producer approved mix - auto-approving song")
        song.status = .approved
        
        do {
            try modelContext.save()
            print("✅ Song auto-approved")
            
            // Sync to Firestore if needed
            if project.firestoreId != nil,
               song.firestoreId != nil {
                Task {
                    // TODO: Add updateSongStatus to FirestoreService if needed
                    print("📤 Syncing song status to Firestore (if implemented)")
                }
            }
        } catch {
            print("❌ Error auto-approving song: \(error)")
        }
    }
    
    private func approvalColor(_ status: ApprovalStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .approved: return .green
        case .changesRequested: return .orange
        }
    }
}

struct ApprovalRowView: View {
    let reviewer: Reviewer
    @Bindable var mix: Mix
    let approval: Approval?
    
    @Environment(AuthenticationService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(\.modelContext) private var modelContext
    
    // Check if this is the current user's approval row
    var isCurrentUser: Bool {
        guard let currentUserId = authService.currentUser?.id,
              let reviewerUserId = reviewer.userId else {
            return false
        }
        return currentUserId == reviewerUserId
    }
    
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
            
            // Show approval status icon for other reviewers
            // Show action buttons for current user
            if isCurrentUser {
                HStack(spacing: 8) {
                    // Show current status if already approved/requested changes
                    if let approval = approval, approval.status != .pending {
                        ApprovalStatusIcon(status: approval.status)
                    }
                    
                    // Always show buttons for current user to change their mind
                    Menu {
                        Button {
                            setApprovalStatus(.approved)
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                        }
                        
                        Button {
                            setApprovalStatus(.changesRequested)
                        } label: {
                            Label("Request Changes", systemImage: "exclamationmark.circle.fill")
                        }
                        
                        if approval?.status != .pending {
                            Button {
                                setApprovalStatus(.pending)
                            } label: {
                                Label("Reset to Pending", systemImage: "clock")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ApprovalStatusIcon(status: approval?.status ?? .pending)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func setApprovalStatus(_ status: ApprovalStatus) {
        print("🎯 Setting approval status to: \(status.rawValue)")
        print("   Reviewer: \(reviewer.displayName)")
        print("   Mix: \(mix.name)")
        
        // Enforce one approval per user per song
        // If approving a mix, clear any other approvals by this user on other mixes of the same song
        if status == .approved, let song = mix.song {
            clearOtherMixApprovals(for: reviewer, in: song)
        }
        
        let approvalToSync: Approval
        
        if let existingApproval = approval {
            // Update existing approval
            existingApproval.status = status
            existingApproval.updatedAt = Date()
            existingApproval.needsUpload = true // Mark for sync
            approvalToSync = existingApproval
            print("✅ Updated existing approval")
        } else {
            // Create new approval
            let newApproval = Approval(status: status, needsUpload: true)
            newApproval.mix = mix
            newApproval.reviewer = reviewer
            modelContext.insert(newApproval)
            approvalToSync = newApproval
            print("✅ Created new approval")
        }
        
        do {
            try modelContext.save()
            print("✅ Approval saved to local database")
            
            // Check if song should be auto-approved (if this is a key approver)
            if status == .approved && reviewer.isKeyApprover {
                checkAndAutoApproveSong()
            }
            
            // Sync to Firestore
            Task {
                await syncApprovalToFirestore(approvalToSync)
            }
        } catch {
            print("❌ Error saving approval: \(error)")
        }
    }
    
    private func syncApprovalToFirestore(_ approval: Approval) async {
        guard let projectId = mix.song?.project?.firestoreId,
              let songId = mix.song?.firestoreId,
              let mixId = mix.firestoreId,
              let reviewerUserId = reviewer.userId else {
            print("⚠️ Cannot sync approval - missing required IDs")
            return
        }
        
        do {
            print("🔄 Syncing approval to Firestore...")
            let approvalId = try await firestoreService.createOrUpdateApproval(
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                approval: approval,
                reviewerUserId: reviewerUserId
            )
            
            // Mark as synced
            await MainActor.run {
                approval.needsUpload = false
                approval.lastSyncedAt = Date()
                try? modelContext.save()
            }
            
            print("✅ Approval synced to Firestore with ID: \(approvalId)")
        } catch {
            print("❌ Failed to sync approval to Firestore: \(error)")
        }
    }
    
    private func clearOtherMixApprovals(for reviewer: Reviewer, in song: Song) {
        // Find all approvals by this reviewer on other mixes in the same song
        for otherMix in song.mixes where otherMix.id != mix.id {
            if let otherApproval = otherMix.approvals.first(where: { $0.reviewer?.id == reviewer.id }) {
                if otherApproval.status == .approved {
                    print("🔄 Clearing previous approval on mix: \(otherMix.name)")
                    otherApproval.status = .pending
                    otherApproval.updatedAt = Date()
                    
                    // Sync to Firestore
                    if let project = song.project,
                       let projectId = project.firestoreId,
                       let songId = song.firestoreId,
                       let mixId = otherMix.firestoreId,
                       let reviewerUserId = reviewer.userId {
                        Task {
                            do {
                                _ = try await firestoreService.createOrUpdateApproval(
                                    projectId: projectId,
                                    songId: songId,
                                    mixId: mixId,
                                    approval: otherApproval,
                                    reviewerUserId: reviewerUserId
                                )
                                print("✅ Cleared approval synced to Firestore")
                            } catch {
                                print("❌ Failed to sync cleared approval: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func checkAndAutoApproveSong() {
        guard let song = mix.song else { return }
        
        // Key approver approved mix - auto-approve the song
        print("🎯 Key approver (\(reviewer.displayName)) approved mix - auto-approving song")
        song.status = .approved
        
        do {
            try modelContext.save()
            print("✅ Song auto-approved")
            
            // Sync to Firestore if needed
            if let project = song.project,
               project.firestoreId != nil,
               song.firestoreId != nil {
                Task {
                    // TODO: Add updateSongStatus to FirestoreService if needed
                    print("📤 Syncing song status to Firestore (if implemented)")
                }
            }
        } catch {
            print("❌ Error auto-approving song: \(error)")
        }
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
