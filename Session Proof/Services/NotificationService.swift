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
    var projectSyncService: ProjectSyncService?

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
        Logger.debug("📱 Requesting notification permissions...")
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            isAuthorized = granted
            
            if granted {
                Logger.debug("✅ Notification permissions granted")
                
                // Register for remote notifications on main thread
                await MainActor.run {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #elseif os(macOS)
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                
                // Don't get FCM token immediately - wait for APNS token to be set
                // The token will be fetched automatically via MessagingDelegate when APNS token is ready
                Logger.debug("✅ Registered for remote notifications - FCM token will be fetched when APNS token is ready")
            } else {
                Logger.error("❌ Notification permissions denied")
            }
            
            return granted
        } catch {
            Logger.error("❌ Error requesting notification permissions: \(error.localizedDescription)")
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
                
                Logger.debug("📱 Notification authorization status: \(settings.authorizationStatus.rawValue)")
                
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
        Logger.debug("🔄 Refreshing FCM token...")
        
        guard let userId = authService.currentUser?.id else {
            Logger.warning("⚠️ Cannot refresh FCM token - no authenticated user")
            return
        }
        
        do {
            let token = try await Messaging.messaging().token()
            await MainActor.run {
                self.fcmToken = token
            }
            Logger.debug("✅ Got FCM token from Firebase Messaging")
            Logger.debug("   Token: \(token.prefix(20))...")
            Logger.debug("   For user: \(userId)")
            
            // Save token to Firestore for this user
            await saveFCMTokenToFirestore(token: token)
        } catch {
            Logger.error("❌ Error getting FCM token: \(error.localizedDescription)")
        }
    }
    
    /// Save FCM token to Firestore user document
    private func saveFCMTokenToFirestore(token: String) async {
        guard let userId = authService.currentUser?.id,
              let userEmail = authService.currentUser?.email,
              let userName = authService.currentUser?.displayName else {
            Logger.warning("⚠️ No authenticated user to save FCM token")
            return
        }
        
        Logger.debug("💾 Saving FCM token to Firestore:")
        Logger.debug("   User ID: \(userId)")
        Logger.debug("   User Email: \(userEmail)")
        Logger.debug("   User Name: \(userName)")
        Logger.debug("   Token: \(token.prefix(20))...") // Only show first 20 chars for security
        
        do {
            try await firestoreService.updateUserFCMToken(userId: userId, fcmToken: token)
            Logger.debug("✅ Successfully saved FCM token to Firestore for user: \(userId)")
            Logger.debug("   Token will be added to fcmTokens array in users/\(userId)")
        } catch {
            Logger.error("❌ Error saving FCM token to Firestore: \(error.localizedDescription)")
        }
    }
    
    /// Delete FCM token when user signs out
    func deleteFCMToken() async {
        guard let userId = authService.currentUser?.id,
              let token = fcmToken else {
            return
        }
        
        do {
            // Delete from Firestore (remove this specific device's token)
            try await firestoreService.deleteUserFCMToken(userId: userId, fcmToken: token)
            
            // Delete from FCM
            try await Messaging.messaging().deleteToken()
            
            await MainActor.run {
                self.fcmToken = nil
            }
            
            Logger.debug("✅ Deleted FCM token for this device")
        } catch {
            Logger.error("❌ Error deleting FCM token: \(error.localizedDescription)")
        }
    }
    
    /// Clear the app badge count
    func clearBadge() {
        Task { @MainActor in
            #if os(iOS)
            if #available(iOS 17.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(0)
            } else {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            #elseif os(macOS)
            NSApplication.shared.dockTile.badgeLabel = nil
            #endif
            Logger.debug("✅ Cleared app badge")
        }
    }

    /// Trigger background sync when certain notifications arrive
    private func handleNotificationSync(userInfo: [AnyHashable: Any]) {
        guard let notificationType = userInfo["type"] as? String else {
            return
        }

        // Trigger sync for notifications that require updated data
        let syncTriggeringTypes = [
            "project_invitation",    // New project invitation
            "new_mix",              // New mix uploaded
            "mix_updated",          // Mix updated
            "approval_status_changed", // Approval changed
            "new_comment"           // New comment added
        ]

        if syncTriggeringTypes.contains(notificationType) {
            Logger.debug("📱 Notification type '\(notificationType)' requires sync - triggering background sync")

            // Post notification to trigger sync in the main app with proper modelContext
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerBackgroundSync"),
                object: nil,
                userInfo: ["notificationType": notificationType]
            )
        }
    }
}

// MARK: - MessagingDelegate
extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Logger.debug("📱 FCM token refreshed via MessagingDelegate")
        
        guard let token = fcmToken else {
            Logger.warning("⚠️ Received nil FCM token")
            return
        }
        
        Logger.debug("   Token: \(token.prefix(20))...")
        
        Task {
            await MainActor.run {
                self.fcmToken = token
            }
            
            // Only save if we have an authenticated user
            if authService.currentUser?.id != nil {
                await saveFCMTokenToFirestore(token: token)
            } else {
                Logger.warning("⚠️ FCM token received but no authenticated user - will save after login")
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
        Logger.debug("📱 Received notification while app in foreground")
        Logger.debug("   Title: \(notification.request.content.title)")
        Logger.debug("   Body: \(notification.request.content.body)")
        Logger.debug("   Sound: \(notification.request.content.sound?.description ?? "none")")
        Logger.debug("   Badge: \(notification.request.content.badge?.intValue ?? 0)")

        let userInfo = notification.request.content.userInfo
        Logger.debug("   Notification data: \(userInfo)")

        // Trigger background sync if needed
        handleNotificationSync(userInfo: userInfo)

        // Show notification even when app is in foreground
        #if os(iOS)
        completionHandler([.banner, .sound, .badge])
        #elseif os(macOS)
        completionHandler([.banner, .sound, .badge])
        #endif
        Logger.debug("   ✅ Called completion handler with [.banner, .sound, .badge]")
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Logger.debug("📱 User tapped notification")

        let userInfo = response.notification.request.content.userInfo
        Logger.debug("   Notification data: \(userInfo)")

        // Trigger background sync if needed
        handleNotificationSync(userInfo: userInfo)

        // Extract deep link data from notification
        if let projectId = userInfo["projectId"] as? String,
           let mixId = userInfo["mixId"] as? String {
            Logger.debug("   Deep link to project: \(projectId), mix: \(mixId)")

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
