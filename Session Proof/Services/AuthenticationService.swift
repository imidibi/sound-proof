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
    var originalTransactionId: String?      // StoreKit original transaction ID (unique per purchase)
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

    /// Can this user create projects? (Must be producer AND have active subscription or trial)
    var canCreateProjects: Bool {
        // Must have producer role
        guard isProducer else { return false }
        
        // Check subscription status
        guard let status = subscriptionStatus else {
            // No subscription info yet - default to false for new users
            return false
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
            Task { [weak self] in
                guard let self = self else { return }
                
                // Add timeout to prevent indefinite loading
                // If profile loading takes more than 3 seconds, assume network issue and show login
                do {
                    try await self.withTimeout(seconds: 3) {
                        await self.loadUserProfile(uid: firebaseUser.uid, email: firebaseUser.email ?? "")
                    }
                } catch {
                    Logger.warning("⚠️ Profile loading timed out - user will need to sign in again")
                    // Sign out the user so they see the login screen instead of hanging
                    try? self.auth.signOut()
                }
                
                // Always set isCheckingAuth to false when done (success or failure)
                await MainActor.run {
                    self.isCheckingAuth = false
                }
            }
        } else {
            // No Firebase user - show login immediately
            isCheckingAuth = false
        }
    }
    
    /// Execute an async operation with a timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private struct TimeoutError: Error {}
    
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
        var data: [String: Any] = [
            "email": user.email,
            "displayName": user.displayName,
            "role": user.role.rawValue,
            "createdAt": Timestamp(date: user.createdAt)
        ]
        
        // For new producer users, set initial subscription status as "free"
        // This ensures they see the paywall before getting access
        if user.subscriptionStatus == nil && user.isProducer {
            data["subscriptionStatus"] = "free"
            data["subscriptionTier"] = "free"
        }
        
        try await db.collection("users").document(user.id).setData(data)
    }
    
    func updateUserProfile(user: User) async throws {
        // Update in Firestore
        try await saveUserProfile(user: user)
        
        // Update local state
        await MainActor.run {
            self.currentUser = user
        }
        
        Logger.debug("✅ User profile updated: \(user.displayName) (\(user.email))")
    }
    
    private func loadUserProfile(uid: String, email: String) async {
        Logger.debug("📥 Loading user profile for UID: \(uid)")
        
        do {
            let document = try await db.collection("users").document(uid).getDocument()
            
            guard document.exists else {
                Logger.error("❌ User profile document does not exist in Firestore for UID: \(uid)")
                Logger.warning("⚠️ This usually means the user was created directly in Firebase Auth without a Firestore profile")
                Logger.debug("🔧 Attempting to create profile automatically...")
                
                // Create a basic profile - we'll prompt user to complete it later
                await createMissingProfile(uid: uid, email: email)
                return
            }
            
            guard let data = document.data() else {
                Logger.error("❌ User profile document exists but has no data")
                return
            }
            
            Logger.debug("📊 User profile data: \(data.keys.joined(separator: ", "))")
            
            guard let email = data["email"] as? String else {
                Logger.error("❌ Missing email field")
                return
            }
            
            guard let displayName = data["displayName"] as? String else {
                Logger.error("❌ Missing displayName field")
                return
            }
            
            guard let roleString = data["role"] as? String else {
                Logger.error("❌ Missing role field")
                return
            }
            
            guard let role = UserRole(rawValue: roleString) else {
                Logger.error("❌ Invalid role value: \(roleString)")
                return
            }
            
            guard let timestamp = data["createdAt"] as? Timestamp else {
                Logger.error("❌ Missing createdAt field")
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
                Logger.debug("✅ User profile loaded successfully: \(user.displayName) (\(user.email))")
            }
        } catch {
            Logger.error("❌ Error loading user profile: \(error)")
            Logger.debug("   Error details: \(error.localizedDescription)")
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
        originalTransactionId: String? = nil,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        subscriptionExpiresAt: Date? = nil,
        gracePeriodEndsAt: Date? = nil
    ) async throws {
        guard let user = currentUser else {
            Logger.warning("⚠️ Cannot update subscription - no current user")
            return
        }

        var updateData: [String: Any] = [
            "subscriptionTier": tier,
            "subscriptionStatus": status
        ]

        if let transactionId = originalTransactionId {
            updateData["originalTransactionId"] = transactionId
        }
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
            Logger.debug("✅ Subscription status updated in Firestore")

            // Update local user object
            await MainActor.run {
                var updatedUser = user
                updatedUser.subscriptionTier = tier
                updatedUser.subscriptionStatus = status
                updatedUser.originalTransactionId = originalTransactionId
                updatedUser.trialStartedAt = trialStartedAt
                updatedUser.trialEndsAt = trialEndsAt
                updatedUser.subscriptionExpiresAt = subscriptionExpiresAt
                updatedUser.subscriptionGracePeriodEndsAt = gracePeriodEndsAt
                self.currentUser = updatedUser
            }
        } catch {
            Logger.error("❌ Failed to update subscription status: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Account Deletion
    
    /// Delete user account and all associated data
    func deleteAccount() async throws {
        guard let user = currentUser else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        guard let firebaseUser = Auth.auth().currentUser else {
            throw NSError(domain: "AuthenticationService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No Firebase user found"])
        }
        
        Logger.debug("🗑️ Starting account deletion for user: \(user.id)")
        
        // Step 1: Delete user document from Firestore
        do {
            try await db.collection("users").document(user.id).delete()
            Logger.debug("✅ Deleted user document from Firestore")
        } catch {
            Logger.warning("⚠️ Failed to delete user document (may not exist): \(error)")
        }
        
        // Step 2: Delete all user's projects and associated data
        // Query all projects where user is owner
        let projectsSnapshot = try await db.collection("projects")
            .whereField("ownerId", isEqualTo: user.id)
            .getDocuments()
        
        for projectDoc in projectsSnapshot.documents {
            let projectId = projectDoc.documentID
            
            // Delete all songs in this project
            let songsSnapshot = try await db.collection("projects").document(projectId)
                .collection("songs")
                .getDocuments()
            
            for songDoc in songsSnapshot.documents {
                let songId = songDoc.documentID
                
                // Delete all mixes in this song
                let mixesSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("mixes")
                    .getDocuments()
                
                for mixDoc in mixesSnapshot.documents {
                    try await mixDoc.reference.delete()
                }
                
                // Delete all approvals in this song
                let approvalsSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("approvals")
                    .getDocuments()
                
                for approvalDoc in approvalsSnapshot.documents {
                    try await approvalDoc.reference.delete()
                }
                
                // Delete all comments in this song
                let commentsSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("comments")
                    .getDocuments()
                
                for commentDoc in commentsSnapshot.documents {
                    try await commentDoc.reference.delete()
                }
                
                // Delete the song
                try await songDoc.reference.delete()
            }
            
            // Delete all reviewers in this project
            let reviewersSnapshot = try await db.collection("projects").document(projectId)
                .collection("reviewers")
                .getDocuments()
            
            for reviewerDoc in reviewersSnapshot.documents {
                try await reviewerDoc.reference.delete()
            }
            
            // Delete the project
            try await projectDoc.reference.delete()
            Logger.debug("✅ Deleted project: \(projectId)")
        }
        
        // Step 3: Anonymize comments and approvals on OTHER users' projects
        // Use collection group query to find all reviewer documents for this user
        Logger.debug("🔍 Searching for projects where user is a reviewer using collection group query")
        let reviewersSnapshot = try await db.collectionGroup("reviewers")
            .whereField("userId", isEqualTo: user.id)
            .getDocuments()
        
        Logger.debug("📧 Found \(reviewersSnapshot.documents.count) reviewer record(s) for user")
        
        // Extract unique project IDs
        var projectIds = Set<String>()
        for reviewerDoc in reviewersSnapshot.documents {
            let pathComponents = reviewerDoc.reference.path.split(separator: "/")
            if pathComponents.count >= 2 {
                let projectId = String(pathComponents[1])
                projectIds.insert(projectId)
            }
        }
        
        Logger.debug("📦 Found \(projectIds.count) unique project(s) where user is a reviewer")
        
        for projectId in projectIds {
            // Get project to check ownership
            let projectDoc = try await db.collection("projects").document(projectId).getDocument()
            guard projectDoc.exists else { continue }
            
            let ownerId = projectDoc.data()?["ownerUserId"] as? String
            
            // Skip if this is the user's own project (already deleted in Step 2)
            if ownerId == user.id {
                Logger.debug("⏭️ Skipping own project: \(projectId)")
                continue
            }
            
            Logger.debug("🔄 Anonymizing user contributions in project: \(projectId)")
            
            // Get all songs in this project
            let songsSnapshot = try await db.collection("projects").document(projectId)
                .collection("songs")
                .getDocuments()
            
            for songDoc in songsSnapshot.documents {
                let songId = songDoc.documentID
                
                // Anonymize comments by this user in song's mixes
                let mixesSnapshot = try await db.collection("projects").document(projectId)
                    .collection("songs").document(songId)
                    .collection("mixes")
                    .getDocuments()
                
                for mixDoc in mixesSnapshot.documents {
                    let mixId = mixDoc.documentID
                    
                    // Anonymize comments
                    let commentsSnapshot = try await db.collection("projects").document(projectId)
                        .collection("songs").document(songId)
                        .collection("mixes").document(mixId)
                        .collection("comments")
                        .whereField("authorId", isEqualTo: user.id)
                        .getDocuments()
                    
                    for commentDoc in commentsSnapshot.documents {
                        try await commentDoc.reference.updateData([
                            "authorId": "deleted-user",
                            "authorName": "Deleted Approver"
                        ])
                    }
                    
                    if !commentsSnapshot.documents.isEmpty {
                        Logger.debug("✅ Anonymized \(commentsSnapshot.documents.count) comment(s) in mix: \(mixId)")
                    }
                    
                    // Anonymize approvals
                    let approvalsSnapshot = try await db.collection("projects").document(projectId)
                        .collection("songs").document(songId)
                        .collection("mixes").document(mixId)
                        .collection("approvals")
                        .whereField("reviewerUserId", isEqualTo: user.id)
                        .getDocuments()
                    
                    for approvalDoc in approvalsSnapshot.documents {
                        try await approvalDoc.reference.updateData([
                            "reviewerUserId": "deleted-user",
                            "reviewerName": "Deleted Approver"
                        ])
                    }
                    
                    if !approvalsSnapshot.documents.isEmpty {
                        Logger.debug("✅ Anonymized \(approvalsSnapshot.documents.count) approval(s) in mix: \(mixId)")
                    }
                }
            }
            
            // Delete all reviewer documents for this user in this project
            let reviewersInProjectSnapshot = try await db.collection("projects").document(projectId)
                .collection("reviewers")
                .whereField("userId", isEqualTo: user.id)
                .getDocuments()
            
            for reviewerDoc in reviewersInProjectSnapshot.documents {
                try await reviewerDoc.reference.delete()
                Logger.debug("🗑️ Deleted reviewer document: \(reviewerDoc.documentID)")
            }
        }
        
        Logger.debug("✅ Anonymized user contributions on other users' projects")
        
        // Step 4: Remove user from any organizations
        if let orgId = user.organizationId {
            do {
                try await db.collection("organizations").document(orgId).updateData([
                    "memberIds": FieldValue.arrayRemove([user.id])
                ])
                Logger.debug("✅ Removed user from organization")
            } catch {
                Logger.warning("⚠️ Failed to remove from organization: \(error)")
            }
        }
        
        // Step 5: Delete pending invitations
        let invitationsSnapshot = try await db.collection("pending_invitations")
            .whereField("inviteeEmail", isEqualTo: user.email)
            .getDocuments()
        
        for invitationDoc in invitationsSnapshot.documents {
            try await invitationDoc.reference.delete()
        }
        
        Logger.debug("✅ Deleted pending invitations")
        
        // Step 6: Delete Firebase Auth account (this must be last)
        try await firebaseUser.delete()
        Logger.debug("✅ Deleted Firebase Auth account")
        
        // Step 7: Clear local state
        await MainActor.run {
            self.currentUser = nil
        }
        
        Logger.debug("✅ Account deletion completed successfully")
    }

    // MARK: - Role Conversion

    /// Check if user has any owned projects in Firestore
    func getUserOwnedProjectsCount(userId: String) async throws -> Int {
        let snapshot = try await db.collection("projects")
            .whereField("ownerUserId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents.count
    }

    /// Convert a producer account to an approver account
    /// This is useful when a producer signed up but only needs approver access
    func convertToApprover() async throws {
        guard let user = currentUser else {
            throw NSError(domain: "AuthenticationService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }

        guard user.isProducer else {
            throw NSError(domain: "AuthenticationService", code: -2, 
                         userInfo: [NSLocalizedDescriptionKey: "User is already an approver"])
        }

        Logger.debug("🔄 Converting user to approver: \(user.email)")

        // Update role and subscription status in Firestore
        try await db.collection("users").document(user.id).updateData([
            "role": UserRole.artist.rawValue,
            "subscriptionTier": "free",
            "subscriptionStatus": "free"
        ])

        // Create new user object with updated role
        let updatedUser = User(
            id: user.id,
            email: user.email,
            displayName: user.displayName,
            role: .artist,
            createdAt: user.createdAt,
            organizationId: user.organizationId,
            organizationName: user.organizationName,
            phone: user.phone,
            title: user.title,
            enablePushNotifications: user.enablePushNotifications,
            enableSMSNotifications: user.enableSMSNotifications,
            enableEmailNotifications: user.enableEmailNotifications,
            isOrganizationAdmin: user.isOrganizationAdmin,
            subscriptionTier: "free",
            subscriptionStatus: "free",
            originalTransactionId: nil,
            trialStartedAt: nil,
            trialEndsAt: nil,
            subscriptionExpiresAt: nil,
            subscriptionGracePeriodEndsAt: nil
        )

        // Update local user object
        await MainActor.run {
            self.currentUser = updatedUser
        }

        Logger.debug("✅ User converted to approver successfully")
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
            Logger.debug("✅ Created missing user profile for: \(email)")

            // Now load the newly created profile
            await loadUserProfile(uid: uid, email: email)
        } catch {
            Logger.error("❌ Failed to create missing profile: \(error)")
        }
    }
}
