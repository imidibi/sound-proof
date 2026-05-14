//
//  Reviewer.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum ReviewerRole: String, Codable {
    case owner = "Owner"
    case reviewer = "Reviewer"
    case viewer = "Viewer"
}

enum ReviewerInviteStatus: String, Codable {
    case notSent = "Not Sent"
    case sent = "Sent"
    case accepted = "Accepted"
    case declined = "Declined"
    case removed = "Removed"
}

@Model
final class Reviewer {
    var id: UUID
    var displayName: String
    var email: String
    var userId: String? // Firebase user ID (populated when they join)
    var role: ReviewerRole
    var inviteStatus: ReviewerInviteStatus
    var createdAt: Date
    var acceptedAt: Date? // When they accepted the invitation
    
    var project: Project?
    
    @Relationship(deleteRule: .cascade, inverse: \Approval.reviewer)
    var approvals: [Approval] = []
    
    init(
        id: UUID = UUID(),
        displayName: String,
        email: String,
        userId: String? = nil,
        role: ReviewerRole = .reviewer,
        inviteStatus: ReviewerInviteStatus = .notSent,
        createdAt: Date = Date(),
        acceptedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.userId = userId
        self.role = role
        self.inviteStatus = inviteStatus
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
    }
}
