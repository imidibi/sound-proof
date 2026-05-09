//
//  Project.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum ProjectStatus: String, Codable {
    case draft = "Draft"
    case inReview = "In Review"
    case revisionsNeeded = "Revisions Needed"
    case approved = "Approved"
    case archived = "Archived"
}

@Model
final class Project {
    var id: UUID
    var name: String
    var clientName: String?
    var ownerUserID: String
    var createdAt: Date
    var updatedAt: Date
    var status: ProjectStatus
    var notes: String?
    
    // Cloud sync fields
    var firestoreId: String? // ID in Firebase
    var shareCode: String? // 6-character code for sharing
    var isSynced: Bool = false // Whether synced to cloud
    var lastSyncedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \Song.project)
    var songs: [Song] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Reviewer.project)
    var reviewers: [Reviewer] = []
    
    init(
        id: UUID = UUID(),
        name: String,
        clientName: String? = nil,
        ownerUserID: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: ProjectStatus = .draft,
        notes: String? = nil,
        firestoreId: String? = nil,
        shareCode: String? = nil,
        isSynced: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.clientName = clientName
        self.ownerUserID = ownerUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.notes = notes
        self.firestoreId = firestoreId
        self.shareCode = shareCode
        self.isSynced = isSynced
        self.lastSyncedAt = lastSyncedAt
    }
}
