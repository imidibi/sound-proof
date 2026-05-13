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
    var voiceNoteURL: URL? // Legacy - for backward compatibility
    var voiceNoteFileName: String? // Relative filename in documents directory
    var drawingData: Data?
    var status: CommentStatus
    var createdAt: Date
    var authorID: String
    var authorName: String
    
    // Computed property to get the current full URL from the relative filename
    var resolvedVoiceNoteURL: URL? {
        if let fileName = voiceNoteFileName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsPath.appendingPathComponent(fileName)
        }
        return voiceNoteURL // Fallback to legacy full URL
    }
    
    var song: Song?
    var mix: Mix?
    
    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        endTimestamp: TimeInterval? = nil,
        text: String = "",
        voiceNoteURL: URL? = nil,
        voiceNoteFileName: String? = nil,
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
        self.voiceNoteFileName = voiceNoteFileName
        self.drawingData = drawingData
        self.status = status
        self.createdAt = createdAt
        self.authorID = authorID
        self.authorName = authorName
    }
}
