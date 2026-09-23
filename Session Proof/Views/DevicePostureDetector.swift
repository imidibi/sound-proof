//
//  DevicePostureDetector.swift
//  Session Proof
//
//  Created for iPhone Duo Support
//

import SwiftUI

#if os(iOS)
import UIKit

/// Detects iPhone Duo display posture and configuration
struct DevicePostureDetector {
    
    /// Represents the display configuration of the device
    enum DisplayConfiguration {
        case standard          // Regular iPhone or outer display
        case duoFullyOpen      // iPhone Duo fully open (inner display)
        case duoHalfOpen       // iPhone Duo at laptop angle (half-open)
    }
    
    /// Detects the current display configuration based on size classes and screen dimensions
    /// - Parameters:
    ///   - horizontalSizeClass: The horizontal size class from the environment
    ///   - verticalSizeClass: The vertical size class from the environment
    ///   - windowScene: Optional window scene to get screen dimensions
    /// - Returns: The detected display configuration
    static func detectConfiguration(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        windowScene: UIWindowScene?
    ) -> DisplayConfiguration {
        
        // iPads also report regular/regular size classes; Duo postures only
        // apply to phone-idiom devices
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return .standard
        }
        
        // Check if we're on the inner display (both size classes are regular)
        let isInnerDisplay = horizontalSizeClass == .regular && verticalSizeClass == .regular
        
        guard isInnerDisplay else {
            // Standard iPhone or outer display
            return .standard
        }
        
        // Get screen dimensions from window scene (not UIScreen.main which is deprecated)
        guard let screen = windowScene?.screen else {
            // Default to fully open if we can't determine
            return .duoFullyOpen
        }
        
        let bounds = screen.bounds
        let width = bounds.width
        let height = bounds.height
        
        // Detect half-open posture based on aspect ratio
        // When half-open, the display is in a landscape-like orientation
        // and typically has a more square-ish aspect ratio due to the fold
        let aspectRatio = max(width, height) / min(width, height)
        
        // Half-open typically has aspect ratio closer to 1.5:1 or less
        // Fully open is more like 4:3 or wider
        if aspectRatio < 1.6 {
            return .duoHalfOpen
        }
        
        return .duoFullyOpen
    }
}

/// Environment key for device posture configuration
struct DevicePostureKey: EnvironmentKey {
    static let defaultValue: DevicePostureDetector.DisplayConfiguration = .standard
}

extension EnvironmentValues {
    var devicePosture: DevicePostureDetector.DisplayConfiguration {
        get { self[DevicePostureKey.self] }
        set { self[DevicePostureKey.self] = newValue }
    }
}

/// View modifier that detects and injects device posture into the environment
struct DevicePostureModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var detectedPosture: DevicePostureDetector.DisplayConfiguration = .standard
    
    func body(content: Content) -> some View {
        content
            .environment(\.devicePosture, detectedPosture)
            .onChange(of: horizontalSizeClass) { _, _ in
                updatePosture()
            }
            .onChange(of: verticalSizeClass) { _, _ in
                updatePosture()
            }
            .onAppear {
                updatePosture()
            }
    }
    
    private func updatePosture() {
        // Get the window scene from the active window
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        
        detectedPosture = DevicePostureDetector.detectConfiguration(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            windowScene: windowScene
        )
    }
}

extension View {
    /// Adds device posture detection to the view hierarchy
    func detectDevicePosture() -> some View {
        modifier(DevicePostureModifier())
    }
}

#endif
