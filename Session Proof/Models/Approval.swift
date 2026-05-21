//
//  Approval.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum ApprovalStatus: String, Codable {
    case pending = "Pending"
    case approved = "Approved"
    case changesRequested = "Changes Requested"
}

@Model
final class Approval {
    var id: UUID
    var status: ApprovalStatus
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Sync tracking fields
    var needsUpload: Bool = false // Flag for pending upload to cloud
    var lastSyncedAt: Date? // Last time synced to Firestore
    
    var mix: Mix?
    var reviewer: Reviewer?
    
    init(
        id: UUID = UUID(),
        status: ApprovalStatus = .pending,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        needsUpload: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.needsUpload = needsUpload
        self.lastSyncedAt = lastSyncedAt
    }
}
