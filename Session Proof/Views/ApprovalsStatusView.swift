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
    
    var approvalStats: (approved: Int, pending: Int, changesRequested: Int, total: Int) {
        let reviewers = project.reviewers.filter { $0.inviteStatus == .accepted }
        let total = reviewers.count
        
        var approved = 0
        var changesRequested = 0
        
        for reviewer in reviewers {
            if let approval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id }) {
                if approval.status == .approved {
                    approved += 1
                } else if approval.status == .changesRequested {
                    changesRequested += 1
                }
            }
        }
        
        let pending = total - approved - changesRequested
        return (approved, pending, changesRequested, total)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                ForEach(project.reviewers.filter { $0.inviteStatus == .accepted }.sorted(by: { $0.displayName < $1.displayName })) { reviewer in
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
    
    var approval: Approval? {
        mix.approvals.first(where: { $0.reviewer?.id == reviewer.id })
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 20)
            
            // Reviewer name
            Text(reviewer.displayName)
                .font(.caption)
            
            Spacer()
            
            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var statusIcon: String {
        guard let approval = approval else {
            return "clock"
        }
        switch approval.status {
        case .approved:
            return "checkmark.circle.fill"
        case .changesRequested:
            return "exclamationmark.circle.fill"
        case .pending:
            return "clock"
        }
    }
    
    private var statusColor: Color {
        guard let approval = approval else {
            return .orange
        }
        switch approval.status {
        case .approved:
            return .green
        case .changesRequested:
            return .red
        case .pending:
            return .orange
        }
    }
    
    private var statusText: String {
        guard let approval = approval else {
            return "Pending"
        }
        switch approval.status {
        case .approved:
            return "Approved"
        case .changesRequested:
            return "Changes Requested"
        case .pending:
            return "Pending"
        }
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
        let reviewers = project.reviewers.filter { $0.inviteStatus == .accepted }
        let total = reviewers.count
        
        guard total > 0 else {
            return "No reviewers"
        }
        
        var approved = 0
        var changesRequested = 0
        
        for reviewer in reviewers {
            if let approval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id }) {
                if approval.status == .approved {
                    approved += 1
                } else if approval.status == .changesRequested {
                    changesRequested += 1
                }
            }
        }
        
        if approved == total {
            return "Fully Approved"
        } else if changesRequested > 0 {
            return "Changes Requested"
        } else {
            return "Pending"
        }
    }
    
    var statusColor: Color {
        switch approvalStatus {
        case "Fully Approved":
            return .green
        case "Changes Requested":
            return .red
        default:
            return .orange
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

struct SongApprovalBadge: View {
    let song: Song
    let project: Project
    
    var approvalStatus: String {
        let mixes = song.mixes
        guard !mixes.isEmpty else {
            return "No mixes"
        }
        
        let reviewers = project.reviewers.filter { $0.inviteStatus == .accepted }
        guard !reviewers.isEmpty else {
            return "No reviewers"
        }
        
        // Check if any mix is fully approved
        for mix in mixes {
            var approved = 0
            for reviewer in reviewers {
                if let approval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id }),
                   approval.status == .approved {
                    approved += 1
                }
            }
            if approved == reviewers.count {
                return "Approved"
            }
        }
        
        // Check if any mix has changes requested
        for mix in mixes {
            for reviewer in reviewers {
                if let approval = mix.approvals.first(where: { $0.reviewer?.id == reviewer.id }),
                   approval.status == .changesRequested {
                    return "In Review"
                }
            }
        }
        
        return "Pending"
    }
    
    var statusColor: Color {
        switch approvalStatus {
        case "Approved":
            return .green
        case "In Review":
            return .orange
        default:
            return .gray
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
