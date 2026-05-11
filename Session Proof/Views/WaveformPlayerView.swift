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
    var inspectorWidth: CGFloat = 0  // Width of inspector overlay if visible
    
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
                            .font(.system(size: timeDisplaySize, weight: .bold, design: .rounded))
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
            #if os(iOS)
            .background(Color(uiColor: .systemGray6).opacity(0.5))
            #else
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            #endif
            
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
                
                // Spacer to account for inspector overlay
                if inspectorWidth > 0 {
                    Spacer()
                        .frame(width: inspectorWidth)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            // Player controls
            HStack {
                Spacer()
                PlayerControlsView(audioPlayerService: audioPlayerService)
                Spacer()
                
                // Spacer to account for inspector overlay
                if inspectorWidth > 0 {
                    Spacer()
                        .frame(width: inspectorWidth)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .task(id: mix.id) {
            await loadAudioAndWaveform()
        }
    }
    
    private var timeDisplaySize: CGFloat {
        #if os(iOS)
        // Smaller font on iPhone
        return UIDevice.current.userInterfaceIdiom == .phone ? 48 : 72
        #else
        return 72
        #endif
    }
    
    private func formatLargeTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    private func loadAudioAndWaveform() async {
        // Check if we need to download from cloud first
        if mix.resolvedAssetURL == nil && mix.cloudURL != nil {
            await downloadMixFromCloud()
        }
        
        guard let url = mix.resolvedAssetURL else {
            downloadError = "No audio file available"
            print("❌ No audio file: assetURL=\(String(describing: mix.assetURL)), fileName=\(String(describing: mix.assetFileName))")
            return
        }
        
        // Verify file exists
        if !FileManager.default.fileExists(atPath: url.path) {
            downloadError = "Audio file not found at path"
            print("❌ Audio file not found at: \(url.path)")
            return
        }
        
        do {
            try audioPlayerService.loadAudio(from: url)
            
            // Check if we have a cached waveform with stereo data
            var needsRegeneration = true
            if let cachedData = mix.waveformCache,
               let cached = try? JSONDecoder().decode(WaveformData.self, from: cachedData) {
                // Only use cache if it has stereo data (rightSamples not empty)
                if !cached.rightSamples.isEmpty {
                    waveformData = cached
                    needsRegeneration = false
                    print("✅ Using cached stereo waveform")
                } else {
                    print("⚠️ Cached waveform is old mono format, regenerating...")
                }
            }
            
            if needsRegeneration {
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
    
    @State private var selectedComment: Comment?
    
    var body: some View {
        GeometryReader { geometry in
            let playheadX: CGFloat = 40 // Fixed position from left edge
            let totalWaveformWidth = geometry.size.width * zoomLevel
            
            ZStack(alignment: .leading) {
                // Dual waveform display (L/R channels)
                VStack(spacing: 0) {
                    // Left channel (top half) - extends down from center
                    ZStack(alignment: .bottom) {
                        Color.clear
                        HStack(spacing: 2) {
                            ForEach(Array(waveformData.leftSamples.enumerated()), id: \.offset) { index, sample in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(waveformBarColor(for: index, totalBars: waveformData.leftSamples.count))
                                    .frame(
                                        width: max(1, (totalWaveformWidth / CGFloat(waveformData.leftSamples.count)) - 2),
                                        height: max(2, CGFloat(sample) * (geometry.size.height / 2) * 0.85)
                                    )
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: geometry.size.height / 2)
                    
                    // Center line separator
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(height: 2)
                    
                    // Right channel (bottom half) - extends up from center
                    ZStack(alignment: .top) {
                        Color.clear
                        HStack(spacing: 2) {
                            ForEach(Array(waveformData.rightSamples.enumerated()), id: \.offset) { index, sample in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(waveformBarColor(for: index, totalBars: waveformData.rightSamples.count))
                                    .frame(
                                        width: max(1, (totalWaveformWidth / CGFloat(waveformData.rightSamples.count)) - 2),
                                        height: max(2, CGFloat(sample) * (geometry.size.height / 2) * 0.85)
                                    )
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(height: geometry.size.height / 2)
                }
                .frame(width: totalWaveformWidth, height: geometry.size.height, alignment: .leading)
                .offset(x: playheadX - waveformScrollOffset(playheadX: playheadX, totalWidth: totalWaveformWidth, viewWidth: geometry.size.width))
                
                // Comment markers
                ForEach(comments) { comment in
                    CommentMarkerView(
                        comment: comment,
                        duration: duration,
                        isSelected: selectedComment?.id == comment.id
                    )
                    .offset(x: commentXPosition(for: comment.timestamp, playheadX: playheadX, totalWidth: totalWaveformWidth, viewWidth: geometry.size.width))
                    .onTapGesture {
                        selectedComment = comment
                        onSeek(comment.timestamp)
                    }
                }
                
                // Fixed playhead at left edge
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 0)
                    .position(x: playheadX, y: geometry.size.height / 2)
                    .zIndex(100)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convert tap/drag position to time relative to playhead
                        let relativeX = value.location.x - playheadX
                        let scrollOffset = waveformScrollOffset(playheadX: playheadX, totalWidth: totalWaveformWidth, viewWidth: geometry.size.width)
                        let pixelOffset = scrollOffset + relativeX
                        let position = pixelOffset / totalWaveformWidth
                        let time = max(0, min(duration, duration * position))
                        onSeek(time)
                    }
            )
        }
    }
    
    // Calculate how much to scroll the waveform to keep current position at playhead
    private func waveformScrollOffset(playheadX: CGFloat, totalWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let playbackPosition = currentTime / duration
        let offset = playbackPosition * totalWidth
        
        // Debug: Log every 1 second
        if Int(currentTime) != Int(currentTime - 0.01) {
            print("📍 Playback: \(String(format: "%.2f", currentTime))s / \(String(format: "%.2f", duration))s = \(String(format: "%.1f", playbackPosition * 100))%")
            print("   Scroll offset: \(Int(offset))px of \(Int(totalWidth))px total")
        }
        
        return offset
    }
    
    private func commentXPosition(for timestamp: TimeInterval, playheadX: CGFloat, totalWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return playheadX }
        let commentPosition = (timestamp / duration) * totalWidth
        let scrollOffset = waveformScrollOffset(playheadX: playheadX, totalWidth: totalWidth, viewWidth: viewWidth)
        return playheadX + (commentPosition - scrollOffset)
    }
    
    // Create gradient color variation around the blue theme
    private func waveformBarColor(for index: Int, totalBars: Int) -> Color {
        // Base colors: #494FFA (median) and #4753EB (gradient variation)
        let baseColor = Color(red: 0x49/255.0, green: 0x4F/255.0, blue: 0xFA/255.0)
        let variationColor = Color(red: 0x47/255.0, green: 0x53/255.0, blue: 0xEB/255.0)
        
        // Create smooth gradient variation across waveform
        let position = Double(index) / Double(max(1, totalBars - 1))
        let wave = sin(position * .pi * 4) * 0.5 + 0.5 // Creates wave pattern 0-1
        
        // Interpolate between the two colors based on wave
        return interpolateColor(from: baseColor, to: variationColor, amount: wave)
    }
    
    private func interpolateColor(from: Color, to: Color, amount: Double) -> Color {
        // Simple linear interpolation between colors
        // In practice, SwiftUI will blend them
        return amount < 0.5 ? from : to
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
    
    private var controlSpacing: CGFloat {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20
        #else
        return 20
        #endif
    }
    
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
            HStack(spacing: controlSpacing) {
                // Return to Zero
                Button {
                    audioPlayerService.seek(to: 0)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                .help("Return to Zero (RTZ)")
                .keyboardShortcut(.return, modifiers: [])
                
                // Rewind
                Button {
                    audioPlayerService.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .help("Skip Backward 15s")
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Spacer()
                
                // Play/Pause
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
                .help(audioPlayerService.isPlaying ? "Pause (Space)" : "Play (Space)")
                .keyboardShortcut(.space, modifiers: [])
                
                Spacer()
                
                // Fast Forward
                Button {
                    audioPlayerService.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .help("Skip Forward 15s")
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                // Skip to End
                Button {
                    audioPlayerService.seek(to: max(0, audioPlayerService.duration - 0.1))
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }
                .help("Skip to End")
                .keyboardShortcut(.return, modifiers: [.shift])
            }
            .buttonStyle(.plain)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}

#Preview {
    let mix = Mix(name: "Mix V1", versionNumber: 1, duration: 180)
    return WaveformPlayerView(mix: mix, audioPlayerService: AudioPlayerService())
}
