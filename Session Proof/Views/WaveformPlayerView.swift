//
//  WaveformPlayerView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct WaveformPlayerView: View {
    @Bindable var mix: Mix
    let audioPlayerService: AudioPlayerService
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectSyncService.self) private var syncService
    @Environment(CloudStorageService.self) private var cloudStorage
    
    @State private var waveformData: WaveformData?
    @State private var isLoadingWaveform = false
    @State private var zoomLevel: Double = 1.0
    @State private var isDownloading = false
    @State private var downloadError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Waveform display
            ZStack {
                if isDownloading {
                    VStack(spacing: 16) {
                        ProgressView(value: cloudStorage.downloadProgress)
                            .frame(width: 200)
                        Text("Downloading mix from cloud...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(cloudStorage.downloadProgress * 100))%")
                            .font(.headline)
                            .monospacedDigit()
                    }
                } else if isLoadingWaveform {
                    ProgressView("Generating waveform...")
                } else if let waveformData = waveformData {
                    WaveformView(
                        waveformData: waveformData,
                        currentTime: audioPlayerService.currentTime,
                        duration: audioPlayerService.duration,
                        zoomLevel: zoomLevel,
                        comments: mix.song?.comments.filter { $0.mix?.id == mix.id } ?? [],
                        onSeek: { time in
                            audioPlayerService.seek(to: time)
                        }
                    )
                    .padding()
                    
                    // Large time display overlay
                    VStack {
                        Text(formatLargeTime(audioPlayerService.currentTime))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.black.opacity(0.3))
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            )
                        
                        Spacer()
                    }
                    .padding(.top, 60)
                } else {
                    Text("Waveform not available")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.1))
            
            // Zoom control
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                
                Slider(value: $zoomLevel, in: 1.0...10.0, step: 0.5)
                    .frame(maxWidth: 400)
                
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                
                Text("\(Int(zoomLevel))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            // Player controls
            PlayerControlsView(audioPlayerService: audioPlayerService)
                .padding()
                .background(.ultraThinMaterial)
        }
        .task(id: mix.id) {
            await loadAudioAndWaveform()
        }
    }
    
    private func formatLargeTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    private func loadAudioAndWaveform() async {
        // Check if we need to download from cloud first
        if mix.assetURL == nil && mix.cloudURL != nil {
            await downloadMixFromCloud()
        }
        
        guard let url = mix.assetURL else {
            downloadError = "No audio file available"
            return
        }
        
        do {
            try audioPlayerService.loadAudio(from: url)
            
            // Check if we have a cached waveform
            if let cachedData = mix.waveformCache,
               let cached = try? JSONDecoder().decode(WaveformData.self, from: cachedData) {
                // Use cached waveform
                waveformData = cached
            } else {
                // Generate new waveform
                isLoadingWaveform = true
                let generated = try await WaveformService.generateWaveform(from: url)
                waveformData = generated
                isLoadingWaveform = false
                
                // Cache the waveform
                if let encoded = try? JSONEncoder().encode(generated) {
                    await MainActor.run {
                        mix.waveformCache = encoded
                    }
                }
            }
        } catch {
            print("Error loading audio or waveform: \(error)")
            isLoadingWaveform = false
        }
    }
    
    private func downloadMixFromCloud() async {
        await MainActor.run {
            isDownloading = true
            downloadError = nil
        }
        
        do {
            try await syncService.downloadMix(
                mix: mix,
                modelContext: modelContext
            )
            
            await MainActor.run {
                isDownloading = false
            }
        } catch {
            await MainActor.run {
                downloadError = error.localizedDescription
                isDownloading = false
            }
        }
    }
}

struct WaveformView: View {
    let waveformData: WaveformData
    let currentTime: TimeInterval
    let duration: TimeInterval
    let zoomLevel: Double
    let comments: [Comment]
    let onSeek: (TimeInterval) -> Void
    
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedComment: Comment?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .leading) {
                    // Waveform bars
                    HStack(spacing: 2) {
                        ForEach(Array(waveformData.samples.enumerated()), id: \.offset) { index, sample in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor(for: index, geometry: geometry))
                                .frame(width: max(1, ((geometry.size.width * zoomLevel) / CGFloat(waveformData.samples.count)) - 2))
                                .frame(height: max(2, CGFloat(sample) * geometry.size.height * 0.8))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Comment markers (should be above waveform)
                    ForEach(comments) { comment in
                        CommentMarkerView(
                            comment: comment,
                            duration: duration,
                            isSelected: selectedComment?.id == comment.id
                        )
                        .offset(x: commentPosition(for: comment.timestamp, in: geometry))
                        .onTapGesture {
                            selectedComment = comment
                            onSeek(comment.timestamp)
                        }
                    }
                    
                    // Playhead (should be on top)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 3)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
                        .offset(x: playheadPosition(in: geometry))
                        .zIndex(100)
                }
                .frame(width: max(geometry.size.width * zoomLevel, geometry.size.width), height: geometry.size.height)
                .padding(.horizontal, 20)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let adjustedX = value.location.x - 20
                            let position = adjustedX / (geometry.size.width * zoomLevel)
                            let time = max(0, min(duration, duration * position))
                            onSeek(time)
                        }
                )
            }
            .defaultScrollAnchor(.center)
        }
    }
    
    private func barColor(for index: Int, geometry: GeometryProxy) -> Color {
        let position = CGFloat(index) / CGFloat(waveformData.samples.count)
        let currentPosition = duration > 0 ? currentTime / duration : 0
        
        return position <= currentPosition ? Color.accentColor : Color.secondary.opacity(0.5)
    }
    
    private func playheadPosition(in geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 20 }
        return 20 + (currentTime / duration) * (geometry.size.width * zoomLevel)
    }
    
    private func commentPosition(for timestamp: TimeInterval, in geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 20 }
        return 20 + (timestamp / duration) * (geometry.size.width * zoomLevel)
    }
}

struct CommentMarkerView: View {
    let comment: Comment
    let duration: TimeInterval
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            // Marker line
            Rectangle()
                .fill(isSelected ? Color.orange : Color.yellow)
                .frame(width: 3)
                .opacity(0.8)
            
            // Comment preview card
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: comment.voiceNoteURL != nil ? "mic.fill" : "text.bubble.fill")
                        .font(.caption2)
                    
                    Text(formatTime(comment.timestamp))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                if !comment.text.isEmpty {
                    Text(comment.text)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.orange.opacity(0.9) : Color.yellow.opacity(0.9))
            )
            .frame(width: 120)
            .shadow(radius: 2)
        }
        .frame(height: 100, alignment: .top)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlayerControlsView: View {
    let audioPlayerService: AudioPlayerService
    
    var body: some View {
        VStack(spacing: 12) {
            // Time display
            HStack {
                Text(formatTime(audioPlayerService.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatTime(audioPlayerService.duration))
                    .font(.caption)
                    .monospacedDigit()
            }
            
            // Transport controls
            HStack(spacing: 24) {
                Button {
                    audioPlayerService.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Spacer()
                
                Button {
                    if audioPlayerService.isPlaying {
                        audioPlayerService.pause()
                    } else {
                        audioPlayerService.play()
                    }
                } label: {
                    Image(systemName: audioPlayerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Spacer()
                
                Button {
                    audioPlayerService.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .buttonStyle(.plain)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}

#Preview {
    let mix = Mix(name: "Mix V1", versionNumber: 1, duration: 180)
    return WaveformPlayerView(mix: mix, audioPlayerService: AudioPlayerService())
}
