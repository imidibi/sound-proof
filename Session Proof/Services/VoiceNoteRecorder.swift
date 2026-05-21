//
//  VoiceNoteRecorder.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import AVFoundation

@Observable
final class VoiceNoteRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    
    var isRecording: Bool = false
    var recordingURL: URL?
    var recordingDuration: TimeInterval = 0
    private var timer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        print("🎤 Setting up audio session...")
        
        #if os(iOS)
        let recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            print("✅ iOS audio session configured")
            
            // Request permission
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    print("🎤 iOS recording permission granted: \(allowed)")
                    if !allowed {
                        print("❌ Recording permission denied")
                    }
                }
            } else {
                recordingSession.requestRecordPermission { allowed in
                    print("🎤 iOS recording permission granted: \(allowed)")
                    if !allowed {
                        print("❌ Recording permission denied")
                    }
                }
            }
        } catch {
            print("❌ Failed to set up iOS recording session: \(error)")
        }
        #elseif os(macOS)
        print("🎤 Checking macOS microphone permission...")
        
        // Check current permission status
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 Current macOS permission status: \(authStatus.rawValue)")
        
        switch authStatus {
        case .notDetermined:
            print("⚠️ Permission not determined - requesting access...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 macOS microphone permission granted: \(granted)")
                if !granted {
                    print("❌ Recording permission denied on macOS")
                    print("💡 Enable in System Settings > Privacy & Security > Microphone")
                } else {
                    print("✅ macOS microphone access granted")
                }
            }
        case .denied, .restricted:
            print("❌ macOS microphone permission denied or restricted")
            print("💡 Please enable microphone access in System Settings > Privacy & Security > Microphone")
        case .authorized:
            print("✅ macOS microphone permission already authorized")
        @unknown default:
            print("⚠️ Unknown permission status")
        }
        #endif
    }
    
    func startRecording() -> URL? {
        print("🎤 Starting voice recording...")
        
        #if os(macOS)
        // Check microphone permission status on macOS
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 macOS microphone permission status: \(authStatus.rawValue)")
        
        switch authStatus {
        case .notDetermined:
            print("⚠️ Microphone permission not determined - requesting access")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 Microphone permission granted: \(granted)")
            }
            return nil
        case .denied, .restricted:
            print("❌ Microphone permission denied or restricted")
            print("💡 Please enable microphone access in System Settings > Privacy & Security > Microphone")
            return nil
        case .authorized:
            print("✅ Microphone permission authorized")
        @unknown default:
            print("⚠️ Unknown microphone permission status")
        }
        #endif
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "voice_note_\(UUID().uuidString).m4a"
        let audioURL = documentsPath.appendingPathComponent(fileName)
        
        print("🎤 Recording to: \(audioURL.path)")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        print("🎤 Audio settings: \(settings)")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            
            let success = audioRecorder?.record() ?? false
            print("🎤 AVAudioRecorder.record() returned: \(success)")
            
            if success {
                isRecording = true
                recordingURL = audioURL
                recordingDuration = 0
                
                startTimer()
                
                print("✅ Recording started successfully")
                return audioURL
            } else {
                print("❌ AVAudioRecorder.record() failed")
                return nil
            }
        } catch {
            print("❌ Could not start recording: \(error)")
            print("   Error domain: \(error as NSError)")
            return nil
        }
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        stopTimer()
        
        return recordingURL
    }
    
    func cancelRecording() {
        audioRecorder?.stop()
        isRecording = false
        stopTimer()
        
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        recordingURL = nil
        recordingDuration = 0
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            self.recordingDuration = recorder.currentTime
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopTimer()
    }
}

extension VoiceNoteRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording was not successful")
            recordingURL = nil
        }
        isRecording = false
        stopTimer()
    }
}
