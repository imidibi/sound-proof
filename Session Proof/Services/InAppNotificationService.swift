//
//  InAppNotificationService.swift
//  Session Proof
//
//  Created by Claude on 5/26/26.
//

import SwiftUI

enum NotificationType {
    case approvalStatusChanged
    case newComment
    case mixUploaded
}

struct InAppNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let timestamp: Date
    
    // Optional data for navigation
    var projectId: String?
    var songId: String?
    var mixId: String?
}

@Observable
class InAppNotificationService {
    var currentNotification: InAppNotification?
    var notificationQueue: [InAppNotification] = []
    private var displayTask: Task<Void, Never>?
    
    func showNotification(
        type: NotificationType,
        title: String,
        message: String,
        projectId: String? = nil,
        songId: String? = nil,
        mixId: String? = nil
    ) {
        let (icon, iconColor) = iconForType(type)
        
        let notification = InAppNotification(
            type: type,
            title: title,
            message: message,
            icon: icon,
            iconColor: iconColor,
            timestamp: Date(),
            projectId: projectId,
            songId: songId,
            mixId: mixId
        )
        
        // Add to queue
        notificationQueue.append(notification)
        
        // Start displaying if not already displaying
        if displayTask == nil {
            displayNextNotification()
        }
    }
    
    private func displayNextNotification() {
        guard !notificationQueue.isEmpty else {
            displayTask = nil
            return
        }
        
        // Show the next notification
        let notification = notificationQueue.removeFirst()
        currentNotification = notification
        
        // Auto-dismiss after 5 seconds and show next
        displayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            if !Task.isCancelled {
                currentNotification = nil
                // Wait a moment before showing next
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                displayNextNotification()
            }
        }
    }
    
    func dismissCurrentNotification() {
        displayTask?.cancel()
        displayTask = nil
        currentNotification = nil
        
        // Show next notification if any
        if !notificationQueue.isEmpty {
            displayNextNotification()
        }
    }
    
    private func iconForType(_ type: NotificationType) -> (String, Color) {
        switch type {
        case .approvalStatusChanged:
            return ("checkmark.circle.fill", .green)
        case .newComment:
            return ("bubble.left.fill", .blue)
        case .mixUploaded:
            return ("arrow.up.circle.fill", .orange)
        }
    }
}
