//
//  AudioPlayerService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import AVFoundation
import Combine

@Observable
final class AudioPlayerService {
    private var audioPlayer: AVAudioPlayer?
    private var timeObserverTimer: Timer?
    
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var audioURL: URL?
    
    init() {
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category to playback with options for routing to external devices
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            )
            
            // Activate the audio session
            try audioSession.setActive(true)
            
            print("✅ Audio session configured for playback with external device support")
            print("   Available outputs: \(audioSession.currentRoute.outputs.map { $0.portType.rawValue })")
        } catch {
            print("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    func loadAudio(from url: URL) throws {
        audioURL = url
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        duration = audioPlayer?.duration ?? 0
        currentTime = 0
        
        if let player = audioPlayer {
            print("🎵 Audio loaded: duration=\(duration)s, url=\(url.lastPathComponent)")
            print("   Format: \(player.format.sampleRate)Hz, \(player.format.channelCount) channels")
            print("   Number of channels: \(player.numberOfChannels)")
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        #if os(iOS)
        // Ensure audio session is active before playing
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Failed to activate audio session: \(error.localizedDescription)")
        }
        #endif
        
        player.play()
        isPlaying = true
        startTimeObserver()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimeObserver()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimeObserver()
        
        #if os(iOS)
        // Deactivate audio session to allow other apps to play audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = min(max(0, time), duration)
        currentTime = player.currentTime
    }
    
    func skipForward(by interval: TimeInterval = 15) {
        seek(to: currentTime + interval)
    }
    
    func skipBackward(by interval: TimeInterval = 15) {
        seek(to: currentTime - interval)
    }
    
    private func startTimeObserver() {
        // Use DisplayLink-compatible timer for smooth 60fps updates
        // RunLoop.common ensures updates even during scrolling/gestures
        timeObserverTimer = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            
            if !player.isPlaying && self.isPlaying {
                self.isPlaying = false
                self.stopTimeObserver()
            }
        }
        RunLoop.main.add(timeObserverTimer!, forMode: .common)
    }
    
    private func stopTimeObserver() {
        timeObserverTimer?.invalidate()
        timeObserverTimer = nil
    }
    
    deinit {
        stopTimeObserver()
    }
}
