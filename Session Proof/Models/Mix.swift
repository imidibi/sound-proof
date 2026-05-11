//
//  Mix.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import SwiftData

enum MixStatus: String, Codable {
    case draft = "Draft"
    case shared = "Shared"
    case inReview = "In Review"
    case approved = "Approved"
    case superseded = "Superseded"
}

@Model
final class Mix {
    var id: UUID
    var name: String
    var versionNumber: Int
    var assetURL: URL? // Local file path
    var assetFileName: String? // Relative filename in documents directory
    var duration: TimeInterval
    var sampleRate: Double
    var channels: Int
    var approvalStatus: MixStatus
    var createdAt: Date
    var notes: String?
    var waveformCache: Data?
    
    // Cloud sync fields
    var cloudURL: String? // Firebase Storage download URL
    var firestoreId: String? // ID in Firebase
    var isUploaded: Bool = false // Whether uploaded to cloud
    var uploadedAt: Date?
    
    var song: Song?
    
    // Computed property to get the current full URL from the relative filename
    var resolvedAssetURL: URL? {
        if let fileName = assetFileName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsPath.appendingPathComponent(fileName)
        }
        return assetURL // Fallback to legacy full URL
    }
    
    @Relationship(deleteRule: .cascade, inverse: \Comment.mix)
    var comments: [Comment] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Approval.mix)
    var approvals: [Approval] = []
    
    init(
        id: UUID = UUID(),
        name: String,
        versionNumber: Int,
        assetURL: URL? = nil,
        assetFileName: String? = nil,
        duration: TimeInterval = 0,
        sampleRate: Double = 44100,
        channels: Int = 2,
        approvalStatus: MixStatus = .draft,
        createdAt: Date = Date(),
        notes: String? = nil,
        waveformCache: Data? = nil,
        cloudURL: String? = nil,
        firestoreId: String? = nil,
        isUploaded: Bool = false,
        uploadedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.versionNumber = versionNumber
        self.assetURL = assetURL
        self.assetFileName = assetFileName
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.approvalStatus = approvalStatus
        self.createdAt = createdAt
        self.notes = notes
        self.waveformCache = waveformCache
        self.cloudURL = cloudURL
        self.firestoreId = firestoreId
        self.isUploaded = isUploaded
        self.uploadedAt = uploadedAt
    }
}
