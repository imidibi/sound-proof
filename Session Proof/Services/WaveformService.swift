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
    let samples: [Float]
    let duration: TimeInterval
    let sampleRate: Double
}

final class WaveformService {
    
    static func generateWaveform(from url: URL, targetSamples: Int = 1000) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }
        
        let reader = try AVAssetReader(asset: asset)
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
        
        var samples: [Float] = []
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        let sampleRate = Double(naturalTimeScale)
        
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
                
                let floatSamples = int16Samples.map { Float($0) / Float(Int16.max) }
                samples.append(contentsOf: floatSamples)
            }
        }
        
        // Downsample to target number of samples
        let downsampledSamples = downsample(samples, to: targetSamples)
        
        return WaveformData(samples: downsampledSamples, duration: duration, sampleRate: sampleRate)
    }
    
    private static func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard samples.count > targetCount else { return samples }
        
        let stride = samples.count / targetCount
        var result: [Float] = []
        
        for i in 0..<targetCount {
            let start = i * stride
            let end = min(start + stride, samples.count)
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
