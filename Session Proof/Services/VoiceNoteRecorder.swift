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
        #if os(iOS)
        let recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            // Request permission
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    if !allowed {
                        print("Recording permission denied")
                    }
                }
            } else {
                recordingSession.requestRecordPermission { allowed in
                    if !allowed {
                        print("Recording permission denied")
                    }
                }
            }
        } catch {
            print("Failed to set up recording session: \(error)")
        }
        #elseif os(macOS)
        // Request microphone permission on macOS
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("Recording permission denied on macOS")
            }
        }
        #endif
    }
    
    func startRecording() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "voice_note_\(UUID().uuidString).m4a"
        let audioURL = documentsPath.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            isRecording = true
            recordingURL = audioURL
            recordingDuration = 0
            
            startTimer()
            
            return audioURL
        } catch {
            print("Could not start recording: \(error)")
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
