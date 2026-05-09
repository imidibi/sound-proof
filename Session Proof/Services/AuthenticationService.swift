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
    case producer
    case client
}

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let role: UserRole
    let createdAt: Date
    
    var isProducer: Bool {
        role == .producer
    }
}

@Observable
class AuthenticationService {
    var currentUser: User?
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    init() {
        // Check if user is already signed in
        if let firebaseUser = auth.currentUser {
            Task {
                await loadUserProfile(uid: firebaseUser.uid)
            }
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
            
            let user = User(
                id: uid,
                email: email,
                displayName: displayName,
                role: role,
                createdAt: timestamp.dateValue()
            )
            
            await MainActor.run {
                self.currentUser = user
            }
        } catch {
            print("Error loading user profile: \(error)")
        }
    }
}
