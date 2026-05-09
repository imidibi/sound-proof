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
    var assetURL: URL?
    var duration: TimeInterval
    var sampleRate: Double
    var channels: Int
    var approvalStatus: MixStatus
    var createdAt: Date
    var notes: String?
    var waveformCache: Data?
    
    var song: Song?
    
    @Relationship(deleteRule: .cascade, inverse: \Comment.mix)
    var comments: [Comment] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Approval.mix)
    var approvals: [Approval] = []
    
    init(
        id: UUID = UUID(),
        name: String,
        versionNumber: Int,
        assetURL: URL? = nil,
        duration: TimeInterval = 0,
        sampleRate: Double = 44100,
        channels: Int = 2,
        approvalStatus: MixStatus = .draft,
        createdAt: Date = Date(),
        notes: String? = nil,
        waveformCache: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.versionNumber = versionNumber
        self.assetURL = assetURL
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.approvalStatus = approvalStatus
        self.createdAt = createdAt
        self.notes = notes
        self.waveformCache = waveformCache
    }
}
