//
//  ApprovalsStatusView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/18/26.
//

import SwiftUI
import SwiftData

struct ApprovalsStatusView: View {
    let project: Project
    let selectedSong: Song? // If nil, show all songs in project
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if let song = selectedSong {
                    // Show single song approval status
                    SongApprovalSection(song: song, project: project)
                } else {
                    // Show all songs in project
                    ForEach(project.songs.sorted(by: { $0.sortOrder < $1.sortOrder })) { song in
                        SongApprovalSection(song: song, project: project)
                    }
                }
            }
            .navigationTitle(selectedSong != nil ? "Approvals: \(selectedSong!.name)" : "Project Approvals")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 800, minHeight: 500)
        #endif
    }
}

struct SongApprovalSection: View {
    let song: Song
    let project: Project
    
    var body: some View {
        Section {
            ForEach(song.mixes.sorted(by: { $0.createdAt > $1.createdAt })) { mix in
                MixApprovalRow(mix: mix, project: project)
            }
        } header: {
            HStack {
                Text(song.name)
                    .font(.headline)
                
                Spacer()
                
                // Overall song approval status
                SongApprovalBadge(song: song, project: project)
            }
        }
    }
}

struct MixApprovalRow: View {
    let mix: Mix
    let project: Project
    @Query private var allApprovals: [Approval]
    @Environment(AuthenticationService.self) private var authService
    
    var allReviewers: [Reviewer] {
        project.reviewers
    }
    
    var acceptedReviewers: [Reviewer] {
        // Include both .accepted and .sent reviewers
        // .sent means they were invited and can participate
        // .accepted means they explicitly joined/were added
        allReviewers.filter { $0.inviteStatus == .accepted || $0.inviteStatus == .sent }
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
        producerInReviewers ? acceptedReviewers.count : acceptedReviewers.count + 1
    }
    
    var approvalStats: (approved: Int, pending: Int, changesRequested: Int, total: Int) {
        let total = totalReviewerCount
        var approved = 0
        var changesRequested = 0
        var pending = 0
        
        // Get approvals for this specific mix
        let mixApprovals = allApprovals.filter { $0.mix?.id == mix.id }
        
        // Count producer approval first if not in reviewers
        if !producerInReviewers {
            if let approval = producerApproval {
                switch approval.status {
                case .approved:
                    approved += 1
                case .changesRequested:
                    changesRequested += 1
                case .pending:
                    pending += 1
                }
            } else {
                // No approval record yet - count as pending
                pending += 1
            }
        }
        
        // Count reviewer approvals
        for reviewer in acceptedReviewers {
            if let approval = mixApprovals.first(where: { $0.reviewer?.id == reviewer.id }) {
                switch approval.status {
                case .approved:
                    approved += 1
                case .changesRequested:
                    changesRequested += 1
                case .pending:
                    pending += 1
                }
            } else {
                // No approval record yet - count as pending
                pending += 1
            }
        }
        
        return (approved, pending, changesRequested, total)
    }
    
    var body: some View {
        let _ = print("🔍 MixApprovalRow for \(mix.name):")
        let _ = print("   - Producer ID: \(project.ownerUserID)")
        let _ = print("   - Producer in reviewers: \(producerInReviewers)")
        let _ = print("   - Total reviewers: \(project.reviewers.count)")
        let _ = print("   - Accepted reviewers: \(acceptedReviewers.count)")
        let _ = print("   - Reviewer user IDs: \(project.reviewers.map { $0.userId ?? "nil" })")
        let _ = print("   - Should show producer row: \(!producerInReviewers)")
        
        return VStack(alignment: .leading, spacing: 12) {
            // Mix header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mix.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(formatDate(mix.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                MixApprovalBadge(mix: mix, project: project)
            }
            
            // Stats summary
            HStack(spacing: 16) {
                StatBadge(
                    count: approvalStats.approved,
                    total: approvalStats.total,
                    label: "Approved",
                    color: .green
                )
                
                StatBadge(
                    count: approvalStats.pending,
                    total: approvalStats.total,
                    label: "Pending",
                    color: .orange
                )
                
                if approvalStats.changesRequested > 0 {
                    StatBadge(
                        count: approvalStats.changesRequested,
                        total: approvalStats.total,
                        label: "Changes",
                        color: .red
                    )
                }
            }
            .font(.caption)
            
            // Individual reviewer status
            VStack(alignment: .leading, spacing: 6) {
                // Show producer first if not already in reviewers
                if !producerInReviewers {
                    ProducerApprovalDisplayRow(
                        mix: mix,
                        project: project,
                        approval: producerApproval
                    )
                }
                
                // Show all approvers
                ForEach(acceptedReviewers.sorted(by: { $0.displayName < $1.displayName })) { reviewer in
                    ReviewerApprovalRow(reviewer: reviewer, mix: mix)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct ReviewerApprovalRow: View {
    let reviewer: Reviewer
    let mix: Mix
    @Environment(AuthenticationService.self) private var authService
    @Query private var allApprovals: [Approval]
    
    // Get the approval record for this reviewer and mix from database query
    var approval: Approval? {
        allApprovals.first(where: { 
            $0.mix?.id == mix.id && $0.reviewer?.id == reviewer.id 
        })
    }
    
    // Check if current user is project owner
    var isProjectOwner: Bool {
        guard let project = mix.song?.project else { return false }
        return project.isOwner(userId: authService.currentUser?.id)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 20)
            
            // Approver name with key approver indicator (only visible to project owner)
            HStack(spacing: 4) {
                Text(reviewer.displayName)
                    .font(.caption)
                
                // Show crown icon for key approver (project owner view only)
                if reviewer.isKeyApprover && isProjectOwner {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            // Status text with timestamp
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let approval = approval, approval.status == .approved {
                    Text(formatDate(approval.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    private var statusIcon: String {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return "checkmark.circle.fill"
            case .changesRequested:
                return "exclamationmark.circle.fill"
            case .pending:
                return "clock"
            }
        } else {
            // No approval record yet - pending
            return "clock"
        }
    }
    
    private var statusColor: Color {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return .green
            case .changesRequested:
                return .red
            case .pending:
                return .orange
            }
        } else {
            return .orange
        }
    }
    
    private var statusText: String {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return "Approved"
            case .changesRequested:
                return "Changes Requested"
            case .pending:
                return "Pending Review"
            }
        } else {
            // No approval record - show based on mix status
            switch mix.approvalStatus {
            case .draft:
                return "Not Shared Yet"
            case .shared, .inReview:
                return "Pending Review"
            case .approved, .superseded:
                return "Pending Review"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StatBadge: View {
    let count: Int
    let total: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)/\(total)")
                .fontWeight(.semibold)
            Text(label)
        }
        .foregroundStyle(color)
    }
}

struct MixApprovalBadge: View {
    let mix: Mix
    let project: Project
    
    var approvalStatus: String {
        let reviewers = project.reviewers.filter { $0.inviteStatus == .accepted || $0.inviteStatus == .sent }
        
        guard reviewers.count > 0 else {
            return "No Approvers"
        }
        
        // Use mix's overall status
        switch mix.approvalStatus {
        case .approved:
            return "Approved"
        case .inReview:
            return "In Review"
        case .shared:
            return "Awaiting Review"
        case .draft:
            return "Draft"
        case .superseded:
            return "Superseded"
        }
    }
    
    var statusColor: Color {
        switch mix.approvalStatus {
        case .approved:
            return .green
        case .inReview, .shared:
            return .orange
        case .draft:
            return .gray
        case .superseded:
            return .purple
        }
    }
    
    var body: some View {
        Text(approvalStatus)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ProducerApprovalDisplayRow: View {
    let mix: Mix
    let project: Project
    let approval: Approval?
    
    @Environment(AuthenticationService.self) private var authService
    
    // Get producer's display name from auth service or project
    var producerDisplayName: String {
        if let currentUser = authService.currentUser, currentUser.id == project.ownerUserID {
            return currentUser.displayName
        }
        return project.producerName ?? "Producer"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 20)
            
            // Producer name with producer label
            HStack(spacing: 4) {
                Text(producerDisplayName)
                    .font(.caption)
                
                Text("(Producer)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status text with timestamp
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let approval = approval, approval.status == .approved {
                    Text(formatDate(approval.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    private var statusIcon: String {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return "checkmark.circle.fill"
            case .changesRequested:
                return "exclamationmark.circle.fill"
            case .pending:
                return "clock"
            }
        } else {
            // No approval record yet - pending
            return "clock"
        }
    }
    
    private var statusColor: Color {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return .green
            case .changesRequested:
                return .red
            case .pending:
                return .orange
            }
        } else {
            return .orange
        }
    }
    
    private var statusText: String {
        if let approval = approval {
            switch approval.status {
            case .approved:
                return "Approved"
            case .changesRequested:
                return "Changes Requested"
            case .pending:
                return "Pending Review"
            }
        } else {
            // No approval record - show based on mix status
            switch mix.approvalStatus {
            case .draft:
                return "Not Shared Yet"
            case .shared, .inReview:
                return "Pending Review"
            case .approved, .superseded:
                return "Pending Review"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct SongApprovalBadge: View {
    let song: Song
    let project: Project
    
    var approvalStatus: String {
        let mixes = song.mixes.filter { !$0.isDeleted }
        guard !mixes.isEmpty else {
            return "No Mixes"
        }
        
        let reviewers = project.reviewers.filter { $0.inviteStatus == .accepted || $0.inviteStatus == .sent }
        guard !reviewers.isEmpty else {
            return "No Approvers"
        }
        
        // Song approval is based on the song's status field, 
        // which is only set to .approved when a key approver/producer approves
        if song.status == .approved {
            return "Approved"
        }
        
        // Check if any mix is in review or shared
        if mixes.contains(where: { $0.approvalStatus == .inReview || $0.approvalStatus == .shared }) {
            return "In Review"
        }
        
        // All are draft
        return "Draft"
    }
    
    var statusColor: Color {
        // Use song's actual approval status (set by key approver)
        if song.status == .approved {
            return .green
        }
        
        let mixes = song.mixes.filter { !$0.isDeleted }
        if mixes.contains(where: { $0.approvalStatus == .inReview || $0.approvalStatus == .shared }) {
            return .orange
        }
        
        return .gray
    }
    
    var body: some View {
        Text(approvalStatus)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
