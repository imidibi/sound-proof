//
//  Logger.swift
//  Session Proof
//
//  Created by Ian Miller on 6/5/26.
//

import Foundation

/// Centralized logging utility for the app
/// Set ENABLE_DEBUG_LOGGING to false for production builds
struct Logger {
    #if DEBUG
    static let ENABLE_DEBUG_LOGGING = true
    #else
    static let ENABLE_DEBUG_LOGGING = false
    #endif
    
    /// Log a debug message (only in debug builds)
    static func debug(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        guard ENABLE_DEBUG_LOGGING else { return }
        let output = items.map { "\($0)" }.joined(separator: separator)
        print(output, terminator: terminator)
    }
    
    /// Log an error message (always logged, even in production)
    static func error(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let output = items.map { "\($0)" }.joined(separator: separator)
        print("❌ ERROR:", output, terminator: terminator)
    }
    
    /// Log a warning message (always logged, even in production)
    static func warning(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let output = items.map { "\($0)" }.joined(separator: separator)
        print("⚠️ WARNING:", output, terminator: terminator)
    }
    
    /// Log an info message (always logged, even in production for critical info)
    static func info(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let output = items.map { "\($0)" }.joined(separator: separator)
        print("ℹ️", output, terminator: terminator)
    }
}
