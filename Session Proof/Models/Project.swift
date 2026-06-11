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

enum ProjectWorkflowStage: String, Codable {
    case tracking = "Tracking"
    case editing = "Editing"
    case mixing = "Mixing"
    case mastering = "Mastering"
    case review = "Review"
    case approved = "Approved"
    case released = "Released"
    case archived = "Archived"
}

@Model
final class Project {
    var id: UUID
    var name: String
    
    // Basic Project Information
    var artistName: String? // Main artist/band name
    var producerName: String? // Lead producer name
    var studioName: String? // Studio name (if applicable)
    var genre: String?
    var releaseDate: Date?
    
    // Legacy field (keep for backwards compatibility)
    var clientName: String?
    
    // Ownership & Personnel
    var ownerUserID: String // User who created the project
    var organizationId: String? // Studio/Organization this belongs to
    var assignedProducerId: String? // Assigned producer user ID
    var assistantEngineerId: String?
    var masteringEngineerId: String?
    var labelContactName: String?
    var labelContactEmail: String?
    var labelContactPhone: String?
    var managerName: String?
    var managerEmail: String?
    var managerPhone: String?
    
    // Workflow
    var workflowStage: ProjectWorkflowStage?
    
    // Legacy status (keep for backwards compatibility)
    var status: ProjectStatus
    
    // Dates
    var createdAt: Date
    var updatedAt: Date
    
    // Notes
    var notes: String?
    
    // Cloud sync fields
    var firestoreId: String? // ID in Firebase
    var shareCode: String? // 6-character code for sharing
    var isSynced: Bool = false // Whether synced to cloud
    var lastSyncedAt: Date?
    
    // Archive fields
    var isArchived: Bool = false
    var archivedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \Song.project)
    var songs: [Song] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Reviewer.project)
    var reviewers: [Reviewer] = []
    
    init(
        id: UUID = UUID(),
        name: String,
        artistName: String? = nil,
        producerName: String? = nil,
        studioName: String? = nil,
        genre: String? = nil,
        releaseDate: Date? = nil,
        clientName: String? = nil,
        ownerUserID: String,
        organizationId: String? = nil,
        assignedProducerId: String? = nil,
        workflowStage: ProjectWorkflowStage? = .tracking,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: ProjectStatus = .draft,
        notes: String? = nil,
        firestoreId: String? = nil,
        shareCode: String? = nil,
        isSynced: Bool = false,
        lastSyncedAt: Date? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.artistName = artistName
        self.producerName = producerName
        self.studioName = studioName
        self.genre = genre
        self.releaseDate = releaseDate
        self.clientName = clientName
        self.ownerUserID = ownerUserID
        self.organizationId = organizationId
        self.assignedProducerId = assignedProducerId
        self.workflowStage = workflowStage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.notes = notes
        self.firestoreId = firestoreId
        self.shareCode = shareCode
        self.isSynced = isSynced
        self.lastSyncedAt = lastSyncedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
    
    // MARK: - Helper Methods
    
    /// Check if the given user ID is the owner of this project
    /// This should be used for permission checks instead of checking user role
    func isOwner(userId: String?) -> Bool {
        guard let userId = userId else { return false }
        return self.ownerUserID == userId
    }
}
