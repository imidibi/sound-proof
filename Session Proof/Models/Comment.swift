//
//  Comment.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum CommentStatus: String, Codable {
    case open = "Open"
    case resolved = "Resolved"
    case rejected = "Rejected"
    case convertedToTask = "Converted to Task"
}

@Model
final class Comment {
    var id: UUID
    var timestamp: TimeInterval
    var endTimestamp: TimeInterval?
    var text: String
    var voiceNoteURL: URL?
    var drawingData: Data?
    var status: CommentStatus
    var createdAt: Date
    var authorID: String
    var authorName: String
    
    var song: Song?
    var mix: Mix?
    
    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        endTimestamp: TimeInterval? = nil,
        text: String = "",
        voiceNoteURL: URL? = nil,
        drawingData: Data? = nil,
        status: CommentStatus = .open,
        createdAt: Date = Date(),
        authorID: String,
        authorName: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.text = text
        self.voiceNoteURL = voiceNoteURL
        self.drawingData = drawingData
        self.status = status
        self.createdAt = createdAt
        self.authorID = authorID
        self.authorName = authorName
    }
}
