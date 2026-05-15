//
//  AuthenticationService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum UserRole: String, Codable {
    case studio        // Studio owner/admin
    case producer      // Producer (can be independent or part of studio)
    case artist        // Artist/Approver (free user)
}

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let role: UserRole
    let createdAt: Date
    
    // Organization membership
    var organizationId: String?     // Firestore ID of Organization
    var organizationName: String?   // Cached for display
    
    // Contact information (for all users)
    var phone: String?
    var title: String? // e.g., "Senior Producer", "Lead Engineer"
    
    // Notification preferences
    var enablePushNotifications: Bool?
    var enableSMSNotifications: Bool?
    var enableEmailNotifications: Bool?
    
    // Studio-specific fields (when role == .studio)
    var isOrganizationAdmin: Bool?
    
    var isProducer: Bool {
        role == .producer || role == .studio
    }
    
    var isStudio: Bool {
        role == .studio
    }
    
    var isArtist: Bool {
        role == .artist
    }
}

@Observable
class AuthenticationService {
    var currentUser: User?
    var isAuthenticated: Bool {
        currentUser != nil
    }
    var isCheckingAuth: Bool = true
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    init() {
        // Check if user is already signed in
        if let firebaseUser = auth.currentUser {
            Task {
                await loadUserProfile(uid: firebaseUser.uid)
                await MainActor.run {
                    self.isCheckingAuth = false
                }
            }
        } else {
            isCheckingAuth = false
        }
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String, displayName: String, role: UserRole) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        
        // Create user profile in Firestore
        let user = User(
            id: result.user.uid,
            email: email,
            displayName: displayName,
            role: role,
            createdAt: Date()
        )
        
        try await saveUserProfile(user: user)
        
        await MainActor.run {
            self.currentUser = user
        }
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        await loadUserProfile(uid: result.user.uid)
    }
    
    func signOut() throws {
        try auth.signOut()
        currentUser = nil
    }
    
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }
    
    // MARK: - User Profile
    
    private func saveUserProfile(user: User) async throws {
        let data: [String: Any] = [
            "email": user.email,
            "displayName": user.displayName,
            "role": user.role.rawValue,
            "createdAt": Timestamp(date: user.createdAt)
        ]
        
        try await db.collection("users").document(user.id).setData(data)
    }
    
    private func loadUserProfile(uid: String) async {
        do {
            let document = try await db.collection("users").document(uid).getDocument()
            
            guard let data = document.data(),
                  let email = data["email"] as? String,
                  let displayName = data["displayName"] as? String,
                  let roleString = data["role"] as? String,
                  let role = UserRole(rawValue: roleString),
                  let timestamp = data["createdAt"] as? Timestamp else {
                return
            }
            
            var user = User(
                id: uid,
                email: email,
                displayName: displayName,
                role: role,
                createdAt: timestamp.dateValue()
            )
            
            // Load optional fields
            user.phone = data["phone"] as? String
            user.title = data["title"] as? String
            user.organizationId = data["organizationId"] as? String
            user.organizationName = data["organizationName"] as? String
            user.enablePushNotifications = data["enablePushNotifications"] as? Bool
            user.enableSMSNotifications = data["enableSMSNotifications"] as? Bool
            user.enableEmailNotifications = data["enableEmailNotifications"] as? Bool
            user.isOrganizationAdmin = data["isOrganizationAdmin"] as? Bool
            
            await MainActor.run {
                self.currentUser = user
            }
        } catch {
            print("Error loading user profile: \(error)")
        }
    }
    
    // MARK: - User Lookup
    
    func getUserByEmail(email: String) async throws -> User? {
        let query = db.collection("users").whereField("email", isEqualTo: email.lowercased())
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first,
              let data = document.data() as? [String: Any],
              let displayName = data["displayName"] as? String,
              let roleString = data["role"] as? String,
              let role = UserRole(rawValue: roleString),
              let timestamp = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        var user = User(
            id: document.documentID,
            email: email,
            displayName: displayName,
            role: role,
            createdAt: timestamp.dateValue()
        )
        
        // Load optional fields
        user.phone = data["phone"] as? String
        user.title = data["title"] as? String
        user.organizationId = data["organizationId"] as? String
        user.organizationName = data["organizationName"] as? String
        
        return user
    }
    
    func getUser(userId: String) async throws -> User? {
        let document = try await db.collection("users").document(userId).getDocument()
        
        guard let data = document.data(),
              let email = data["email"] as? String,
              let displayName = data["displayName"] as? String,
              let roleString = data["role"] as? String,
              let role = UserRole(rawValue: roleString),
              let timestamp = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        var user = User(
            id: userId,
            email: email,
            displayName: displayName,
            role: role,
            createdAt: timestamp.dateValue()
        )
        
        // Load optional fields
        user.phone = data["phone"] as? String
        user.title = data["title"] as? String
        user.organizationId = data["organizationId"] as? String
        user.organizationName = data["organizationName"] as? String
        
        return user
    }
    
    func updateUserProfile(userId: String, data: [String: Any]) async throws {
        try await db.collection("users").document(userId).updateData(data)
        
        // Reload current user if updating self
        if userId == currentUser?.id {
            await loadUserProfile(uid: userId)
        }
    }
}
