//
//  Organization.swift
//  Session Proof
//
//  Created by Ian Miller on 5/14/26.
//

import Foundation
import SwiftData

enum OrganizationType: String, Codable {
    case studio
    case independent // For independent producers
}

@Model
final class Organization {
    var id: UUID
    var firestoreId: String? // Firestore document ID
    var name: String
    var type: OrganizationType
    
    // Contact Information
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var country: String?
    var phone: String?
    var email: String?
    var website: String?
    
    // Business Information
    var taxId: String?
    var notes: String?
    
    // License Information
    var licenseType: String? // "studio" or "producer"
    var licenseStartDate: Date?
    var licenseExpiryDate: Date?
    var maxProducers: Int // Number of producers allowed
    var isActive: Bool
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    
    // Member tracking (User IDs from Firebase)
    var memberIds: [String] = [] // Array of Firebase user IDs
    
    init(
        name: String,
        type: OrganizationType,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zipCode: String? = nil,
        country: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil,
        licenseType: String? = nil,
        maxProducers: Int = 1
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.address = address
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
        self.phone = phone
        self.email = email
        self.website = website
        self.licenseType = licenseType
        self.maxProducers = maxProducers
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
