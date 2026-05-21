//
//  Song.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum SongStatus: String, Codable {
    // Legacy values for backward compatibility
    case draft = "Draft"
    case inProgress = "In Progress"
    case mixingComplete = "Mixing Complete"
    
    // New values
    case inReview = "In Review"
    case revisionsNeeded = "Revisions Needed"
    case approved = "Approved"
    case archived = "Archived"
}

@Model
final class Song {
    var id: UUID
    var name: String
    var artist: String?
    var notes: String?
    var status: SongStatus
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    
    // Cloud sync fields
    var firestoreId: String?
    var needsUpload: Bool = false // Flag for pending upload to cloud
    var lastSyncedAt: Date? // Last time synced to Firestore
    
    var project: Project?
    
    @Relationship(deleteRule: .cascade, inverse: \Mix.song)
    var mixes: [Mix] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Comment.song)
    var comments: [Comment] = []
    
    init(
        id: UUID = UUID(),
        name: String,
        artist: String? = nil,
        notes: String? = nil,
        status: SongStatus = .inReview,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0,
        needsUpload: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.needsUpload = needsUpload
        self.lastSyncedAt = lastSyncedAt
    }
}
