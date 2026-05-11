//
//  WaveformService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import Foundation
import AVFoundation
import Accelerate

struct WaveformData: Codable {
    let leftSamples: [Float]
    let rightSamples: [Float]
    let duration: TimeInterval
    let sampleRate: Double
    
    // Legacy support for mono files
    var samples: [Float] {
        leftSamples
    }
    
    var isStereo: Bool {
        !rightSamples.isEmpty
    }
}

final class WaveformService {
    
    static func generateWaveform(from url: URL, targetSamples: Int = 1000) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }
        
        // Get channel count to handle stereo properly
        let formatDescriptions = try await track.load(.formatDescriptions)
        var channelCount = 1
        if let formatDescription = formatDescriptions.first {
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                channelCount = Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
            }
        }
        
        print("🎵 Audio has \(channelCount) channel(s)")
        
        let reader = try AVAssetReader(asset: asset)
        // Keep original channel count for proper L/R separation
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var leftSamples: [Float] = []
        var rightSamples: [Float] = []
        var totalFramesRead = 0
        
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                
                data.withUnsafeMutableBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                }
                
                // Convert Int16 samples to Float
                let int16Samples = data.withUnsafeBytes {
                    Array(UnsafeBufferPointer<Int16>(start: $0.baseAddress?.assumingMemoryBound(to: Int16.self), count: length / MemoryLayout<Int16>.size))
                }
                
                // Separate interleaved stereo samples (L,R,L,R...) or handle mono
                if channelCount == 2 {
                    for i in stride(from: 0, to: int16Samples.count, by: 2) {
                        leftSamples.append(Float(int16Samples[i]) / Float(Int16.max))
                        if i + 1 < int16Samples.count {
                            rightSamples.append(Float(int16Samples[i + 1]) / Float(Int16.max))
                        }
                    }
                    totalFramesRead += int16Samples.count / 2
                } else {
                    // Mono - use same samples for both channels
                    let floatSamples = int16Samples.map { Float($0) / Float(Int16.max) }
                    leftSamples.append(contentsOf: floatSamples)
                    rightSamples.append(contentsOf: floatSamples)
                    totalFramesRead += int16Samples.count
                }
            }
        }
        
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        let sampleRate = Double(naturalTimeScale)
        
        print("🔍 Sample rate info:")
        print("   naturalTimeScale: \(naturalTimeScale)")
        print("   Using sampleRate: \(sampleRate)Hz")
        
        let expectedFrames = Int(duration * sampleRate)
        print("📊 Read \(totalFramesRead) audio frames (\(channelCount) channel(s)) at \(sampleRate)Hz")
        print("   Expected frames for \(duration)s: \(expectedFrames)")
        print("   L: \(leftSamples.count) samples, R: \(rightSamples.count) samples")
        print("   Ratio: \(Double(totalFramesRead) / Double(expectedFrames))")
        
        // Downsample each channel to target number of samples
        let downsampledLeft = downsample(leftSamples, to: targetSamples)
        let downsampledRight = downsample(rightSamples, to: targetSamples)
        
        print("🎵 Waveform generated: \(leftSamples.count) raw → \(downsampledLeft.count) display samples per channel")
        print("   Samples per display bar: \(Double(leftSamples.count) / Double(targetSamples))")
        
        return WaveformData(
            leftSamples: downsampledLeft,
            rightSamples: downsampledRight,
            duration: duration,
            sampleRate: sampleRate
        )
    }
    
    private static func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard samples.count > targetCount else { return samples }
        
        var result: [Float] = []
        let ratio = Double(samples.count) / Double(targetCount)
        
        for i in 0..<targetCount {
            // Use precise floating-point positioning to avoid drift
            let startFloat = Double(i) * ratio
            let endFloat = Double(i + 1) * ratio
            
            let start = Int(startFloat)
            let end = min(Int(endFloat), samples.count)
            
            guard start < end else {
                result.append(0)
                continue
            }
            
            let chunk = samples[start..<end]
            
            // Use RMS for better visual representation
            let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
            result.append(rms)
        }
        
        return result
    }
}

enum WaveformError: Error {
    case noAudioTrack
    case readError
}
