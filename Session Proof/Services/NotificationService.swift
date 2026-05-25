//
//  NotificationService.swift
//  Session Proof
//
//  Handles Firebase Cloud Messaging setup, token management, and notification permissions
//

import Foundation
import FirebaseMessaging
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
class NotificationService: NSObject {
    var fcmToken: String?
    var isAuthorized: Bool = false
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let authService: AuthenticationService
    private let firestoreService: FirestoreService
    
    init(authService: AuthenticationService, firestoreService: FirestoreService) {
        self.authService = authService
        self.firestoreService = firestoreService
        super.init()
        
        // Set up messaging delegate
        Messaging.messaging().delegate = self
        
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Check current authorization status
        checkAuthorizationStatus()
    }
    
    /// Request notification permissions from the user
    func requestPermissions() async -> Bool {
        print("📱 Requesting notification permissions...")
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            isAuthorized = granted
            
            if granted {
                print("✅ Notification permissions granted")
                
                // Register for remote notifications on main thread
                await MainActor.run {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #elseif os(macOS)
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                
                // Get and save FCM token
                await refreshFCMToken()
            } else {
                print("❌ Notification permissions denied")
            }
            
            return granted
        } catch {
            print("❌ Error requesting notification permissions: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check current notification authorization status
    func checkAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
                
                print("📱 Notification authorization status: \(settings.authorizationStatus.rawValue)")
                
                // If authorized, ensure we're registered for remote notifications
                if isAuthorized {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #elseif os(macOS)
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            }
        }
    }
    
    /// Refresh and save FCM token to Firestore
    func refreshFCMToken() async {
        do {
            let token = try await Messaging.messaging().token()
            await MainActor.run {
                self.fcmToken = token
            }
            print("✅ Got FCM token: \(token)")
            
            // Save token to Firestore for this user
            await saveFCMTokenToFirestore(token: token)
        } catch {
            print("❌ Error getting FCM token: \(error.localizedDescription)")
        }
    }
    
    /// Save FCM token to Firestore user document
    private func saveFCMTokenToFirestore(token: String) async {
        guard let userId = authService.currentUser?.id else {
            print("⚠️ No authenticated user to save FCM token")
            return
        }
        
        do {
            try await firestoreService.updateUserFCMToken(userId: userId, fcmToken: token)
            print("✅ Saved FCM token to Firestore for user: \(userId)")
        } catch {
            print("❌ Error saving FCM token to Firestore: \(error.localizedDescription)")
        }
    }
    
    /// Delete FCM token when user signs out
    func deleteFCMToken() async {
        guard let userId = authService.currentUser?.id else {
            return
        }
        
        do {
            // Delete from Firestore
            try await firestoreService.deleteUserFCMToken(userId: userId)
            
            // Delete from FCM
            try await Messaging.messaging().deleteToken()
            
            await MainActor.run {
                self.fcmToken = nil
            }
            
            print("✅ Deleted FCM token")
        } catch {
            print("❌ Error deleting FCM token: \(error.localizedDescription)")
        }
    }
}

// MARK: - MessagingDelegate
extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token refreshed: \(fcmToken ?? "nil")")
        
        Task {
            await MainActor.run {
                self.fcmToken = fcmToken
            }
            
            if let token = fcmToken {
                await saveFCMTokenToFirestore(token: token)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📱 Received notification while app in foreground")
        
        let userInfo = notification.request.content.userInfo
        print("   Notification data: \(userInfo)")
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📱 User tapped notification")
        
        let userInfo = response.notification.request.content.userInfo
        print("   Notification data: \(userInfo)")
        
        // Extract deep link data from notification
        if let projectId = userInfo["projectId"] as? String,
           let mixId = userInfo["mixId"] as? String {
            print("   Deep link to project: \(projectId), mix: \(mixId)")
            
            // Post notification to handle deep link navigation
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToMix"),
                object: nil,
                userInfo: ["projectId": projectId, "mixId": mixId]
            )
        }
        
        completionHandler()
    }
}
