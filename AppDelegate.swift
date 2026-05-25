//
//  AppDelegate.swift
//  Session Proof
//
//  Handles APNS device token registration for Firebase Cloud Messaging
//

import Foundation
import FirebaseMessaging

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNS device token received")
        
        // Pass APNS token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        print("✅ APNS token set in Firebase Messaging")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

#elseif os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNS device token received")
        
        // Pass APNS token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        print("✅ APNS token set in Firebase Messaging")
    }
    
    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
#endif
