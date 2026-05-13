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
    var voiceNoteCloudURL: String? // Cloud storage URL for re-downloading if needed
    var drawingData: Data?
    var status: CommentStatus
    var createdAt: Date
    var authorID: String
    var authorName: String
    
    // Sync tracking
    var needsSync: Bool = true // True if not yet synced to cloud
    var lastSyncAttempt: Date? // Last time we tried to sync
    var syncError: String? // Last sync error message if any
    
    // Computed property to get the current full URL from the relative filename
    var resolvedVoiceNoteURL: URL? {
        if let fileName = voiceNoteFileName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let resolvedURL = documentsPath.appendingPathComponent(fileName)
            
            // Debug: check if file exists
            let exists = FileManager.default.fileExists(atPath: resolvedURL.path)
            if !exists {
                print("⚠️ Voice note file not found for comment:")
                print("   Comment ID: \(id)")
                print("   Filename: \(fileName)")
                print("   Resolved path: \(resolvedURL.path)")
                print("   Documents directory: \(documentsPath.path)")
            }
            
            return resolvedURL
        }
        
        // Fallback to legacy full URL
        if let legacyURL = voiceNoteURL {
            let exists = FileManager.default.fileExists(atPath: legacyURL.path)
            if !exists {
                print("⚠️ Legacy voice note URL file not found:")
                print("   Comment ID: \(id)")
                print("   Legacy URL: \(legacyURL)")
            }
            return legacyURL
        }
        
        return nil
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
        voiceNoteCloudURL: String? = nil,
        drawingData: Data? = nil,
        status: CommentStatus = .open,
        createdAt: Date = Date(),
        authorID: String,
        authorName: String,
        needsSync: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.text = text
        self.voiceNoteURL = voiceNoteURL
        self.voiceNoteFileName = voiceNoteFileName
        self.voiceNoteCloudURL = voiceNoteCloudURL
        self.drawingData = drawingData
        self.status = status
        self.createdAt = createdAt
        self.authorID = authorID
        self.authorName = authorName
        self.needsSync = needsSync
    }
}
