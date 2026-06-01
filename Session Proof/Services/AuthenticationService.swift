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

    // Subscription fields (StoreKit)
    var subscriptionTier: String?           // "free" or "producer"
    var subscriptionStatus: String?         // "active", "trial", "expired", "cancelled", "free"
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var subscriptionExpiresAt: Date?
    var subscriptionGracePeriodEndsAt: Date?

    // MARK: - Computed Properties

    var isProducer: Bool {
        role == .producer || role == .studio
    }

    var isStudio: Bool {
        role == .studio
    }

    var isArtist: Bool {
        role == .artist
    }

    /// Can this user create projects? (Has active subscription or trial)
    var canCreateProjects: Bool {
        guard let status = subscriptionStatus else {
            // No subscription info yet - allow based on role for backward compatibility
            return isProducer
        }
        return status == "active" || status == "trial"
    }

    /// Is user currently in trial period?
    var isInTrial: Bool {
        subscriptionStatus == "trial"
    }

    /// Is user in grace period after subscription expired?
    var isInGracePeriod: Bool {
        subscriptionStatus == "expired"
    }

    /// Days remaining in trial
    var trialDaysRemaining: Int? {
        guard let trialEnd = trialEndsAt else { return nil }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd)
        return max(0, components.day ?? 0)
    }

    /// Days remaining in grace period
    var gracePeriodDaysRemaining: Int? {
        guard let graceEnd = subscriptionGracePeriodEndsAt else { return nil }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: graceEnd)
        return max(0, components.day ?? 0)
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
                await loadUserProfile(uid: firebaseUser.uid, email: firebaseUser.email ?? "")
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
        // Always use lowercase email for consistency
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let result = try await auth.createUser(withEmail: normalizedEmail, password: password)
        
        // Create user profile in Firestore
        let user = User(
            id: result.user.uid,
            email: normalizedEmail,
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
        // Always use lowercase email for consistency
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let result = try await auth.signIn(withEmail: normalizedEmail, password: password)
        await loadUserProfile(uid: result.user.uid, email: result.user.email ?? normalizedEmail)
    }
    
    func signOut() throws {
        try auth.signOut()
        currentUser = nil
    }
    
    func resetPassword(email: String) async throws {
        // Always use lowercase email for consistency
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        try await auth.sendPasswordReset(withEmail: normalizedEmail)
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
    
    func updateUserProfile(user: User) async throws {
        // Update in Firestore
        try await saveUserProfile(user: user)
        
        // Update local state
        await MainActor.run {
            self.currentUser = user
        }
        
        print("✅ User profile updated: \(user.displayName) (\(user.email))")
    }
    
    private func loadUserProfile(uid: String, email: String) async {
        print("📥 Loading user profile for UID: \(uid)")
        
        do {
            let document = try await db.collection("users").document(uid).getDocument()
            
            guard document.exists else {
                print("❌ User profile document does not exist in Firestore for UID: \(uid)")
                print("⚠️ This usually means the user was created directly in Firebase Auth without a Firestore profile")
                print("🔧 Attempting to create profile automatically...")
                
                // Create a basic profile - we'll prompt user to complete it later
                await createMissingProfile(uid: uid, email: email)
                return
            }
            
            guard let data = document.data() else {
                print("❌ User profile document exists but has no data")
                return
            }
            
            print("📊 User profile data: \(data.keys.joined(separator: ", "))")
            
            guard let email = data["email"] as? String else {
                print("❌ Missing email field")
                return
            }
            
            guard let displayName = data["displayName"] as? String else {
                print("❌ Missing displayName field")
                return
            }
            
            guard let roleString = data["role"] as? String else {
                print("❌ Missing role field")
                return
            }
            
            guard let role = UserRole(rawValue: roleString) else {
                print("❌ Invalid role value: \(roleString)")
                return
            }
            
            guard let timestamp = data["createdAt"] as? Timestamp else {
                print("❌ Missing createdAt field")
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

            // Load subscription fields
            user.subscriptionTier = data["subscriptionTier"] as? String
            user.subscriptionStatus = data["subscriptionStatus"] as? String
            if let timestamp = data["trialStartedAt"] as? Timestamp {
                user.trialStartedAt = timestamp.dateValue()
            }
            if let timestamp = data["trialEndsAt"] as? Timestamp {
                user.trialEndsAt = timestamp.dateValue()
            }
            if let timestamp = data["subscriptionExpiresAt"] as? Timestamp {
                user.subscriptionExpiresAt = timestamp.dateValue()
            }
            if let timestamp = data["subscriptionGracePeriodEndsAt"] as? Timestamp {
                user.subscriptionGracePeriodEndsAt = timestamp.dateValue()
            }

            await MainActor.run {
                self.currentUser = user
                print("✅ User profile loaded successfully: \(user.displayName) (\(user.email))")
            }
        } catch {
            print("❌ Error loading user profile: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - User Lookup
    
    func getUserByEmail(email: String) async throws -> User? {
        let query = db.collection("users").whereField("email", isEqualTo: email.lowercased())
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        let data = document.data()
        
        guard let displayName = data["displayName"] as? String,
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
            await loadUserProfile(uid: userId, email: currentUser?.email ?? "")
        }
    }
    
    // MARK: - Subscription Management

    /// Update subscription status in Firestore from SubscriptionService
    func updateSubscriptionStatus(
        tier: String,
        status: String,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        subscriptionExpiresAt: Date? = nil,
        gracePeriodEndsAt: Date? = nil
    ) async throws {
        guard let user = currentUser else {
            print("⚠️ Cannot update subscription - no current user")
            return
        }

        var updateData: [String: Any] = [
            "subscriptionTier": tier,
            "subscriptionStatus": status
        ]

        if let trialStarted = trialStartedAt {
            updateData["trialStartedAt"] = Timestamp(date: trialStarted)
        }
        if let trialEnds = trialEndsAt {
            updateData["trialEndsAt"] = Timestamp(date: trialEnds)
        }
        if let subExpires = subscriptionExpiresAt {
            updateData["subscriptionExpiresAt"] = Timestamp(date: subExpires)
        }
        if let graceEnds = gracePeriodEndsAt {
            updateData["subscriptionGracePeriodEndsAt"] = Timestamp(date: graceEnds)
        }

        do {
            try await db.collection("users").document(user.id).updateData(updateData)
            print("✅ Subscription status updated in Firestore")

            // Update local user object
            await MainActor.run {
                var updatedUser = user
                updatedUser.subscriptionTier = tier
                updatedUser.subscriptionStatus = status
                updatedUser.trialStartedAt = trialStartedAt
                updatedUser.trialEndsAt = trialEndsAt
                updatedUser.subscriptionExpiresAt = subscriptionExpiresAt
                updatedUser.subscriptionGracePeriodEndsAt = gracePeriodEndsAt
                self.currentUser = updatedUser
            }
        } catch {
            print("❌ Failed to update subscription status: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Migration Helper

    private func createMissingProfile(uid: String, email: String) async {
        // Create a temporary profile with minimal info
        // The user will be prompted to complete it on first login
        let user = User(
            id: uid,
            email: email,
            displayName: email.components(separatedBy: "@").first ?? "User",
            role: .producer, // Default to producer, can be changed later
            createdAt: Date()
        )

        do {
            try await saveUserProfile(user: user)
            print("✅ Created missing user profile for: \(email)")

            // Now load the newly created profile
            await loadUserProfile(uid: uid, email: email)
        } catch {
            print("❌ Failed to create missing profile: \(error)")
        }
    }
}
