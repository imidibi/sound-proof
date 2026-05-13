//
//  NetworkMonitor.swift
//  Session Proof
//
//  Created by Ian Miller on 5/12/26.
//

import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    var isConnected = false
    var connectionType: NWInterface.InterfaceType?
    
    // Callback when connection is restored
    var onConnectionRestored: (() -> Void)?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let wasConnected = self.isConnected
            let nowConnected = path.status == .satisfied
            
            Task { @MainActor in
                self.isConnected = nowConnected
                self.connectionType = path.availableInterfaces.first?.type
                
                // Trigger callback when connection is restored
                if !wasConnected && nowConnected {
                    print("🌐 Network connection restored")
                    self.onConnectionRestored?()
                } else if wasConnected && !nowConnected {
                    print("📵 Network connection lost")
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
    
    deinit {
        stopMonitoring()
    }
}
