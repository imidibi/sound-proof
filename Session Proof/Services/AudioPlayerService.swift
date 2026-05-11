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
    
    init() {}
    
    func loadAudio(from url: URL) throws {
        audioURL = url
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        duration = audioPlayer?.duration ?? 0
        currentTime = 0
    }
    
    func play() {
        guard let player = audioPlayer else { return }
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
        timeObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            
            if !player.isPlaying && self.isPlaying {
                self.isPlaying = false
                self.stopTimeObserver()
            }
        }
    }
    
    private func stopTimeObserver() {
        timeObserverTimer?.invalidate()
        timeObserverTimer = nil
    }
    
    deinit {
        stopTimeObserver()
    }
}
