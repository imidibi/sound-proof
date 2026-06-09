//
//  AppDelegate.swift
//  Session Proof
//
//  Handles APNS device token registration for Firebase Cloud Messaging
//

import Foundation
import FirebaseCore
import FirebaseMessaging

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure Firebase FIRST, before any UI is created
        // This ensures Firebase is ready but doesn't block the UI thread
        FirebaseApp.configure()
        print("✅ Firebase configured in AppDelegate")
        return true
    }
    
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure Firebase FIRST, before any UI is created
        // This ensures Firebase is ready but doesn't block the UI thread
        FirebaseApp.configure()
        print("✅ Firebase configured in AppDelegate")
    }
    
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
