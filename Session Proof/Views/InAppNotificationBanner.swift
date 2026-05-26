//
//  InAppNotificationBanner.swift
//  Session Proof
//
//  Created by Claude on 5/26/26.
//

import SwiftUI

struct InAppNotificationBanner: View {
    let notification: InAppNotification
    let onDismiss: () -> Void
    let onTap: () -> Void
    
    @State private var offset: CGFloat = -100
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: notification.icon)
                    .font(.title2)
                    .foregroundStyle(notification.iconColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .offset(y: offset)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
            }
        }
    }
}

struct InAppNotificationOverlay: View {
    var notificationService: InAppNotificationService
    
    var body: some View {
        if let notification = notificationService.currentNotification {
            VStack {
                InAppNotificationBanner(
                    notification: notification,
                    onDismiss: {
                        notificationService.dismissCurrentNotification()
                    },
                    onTap: {
                        // TODO: Navigate to the relevant content
                        print("📍 Navigate to: \(notification.projectId ?? "none")")
                        notificationService.dismissCurrentNotification()
                    }
                )
                .padding(.top, 8)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
        }
    }
}

#Preview {
    VStack {
        InAppNotificationBanner(
            notification: InAppNotification(
                type: .approvalStatusChanged,
                title: "Mix Approved",
                message: "Test Artist4 approved 'Hello there' in Test Project 2",
                icon: "checkmark.circle.fill",
                iconColor: .green,
                timestamp: Date()
            ),
            onDismiss: {},
            onTap: {}
        )
        
        Spacer()
    }
    .padding()
}
