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
    @State private var verticalScale: Double = 1.5
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
                        duration: mix.duration,
                        zoomLevel: zoomLevel,
                        verticalScale: verticalScale,
                        comments: mix.song?.comments.filter { $0.mix?.id == mix.id } ?? [],
                        onSeek: { time in
                            audioPlayerService.seek(to: time)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    
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
            
            // Zoom and Scale controls
            HStack(spacing: 12) {
                // Horizontal zoom
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
                
                Slider(value: $zoomLevel, in: 1.0...10.0, step: 0.5)
                    .frame(maxWidth: 300)
                
                Text("\(Int(zoomLevel))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                
                Divider()
                    .frame(height: 20)
                
                // Vertical scale
                Image(systemName: "arrow.up.and.down")
                    .foregroundStyle(.secondary)
                
                Slider(value: $verticalScale, in: 0.5...3.0, step: 0.1)
                    .frame(maxWidth: 300)
                
                Text("\(Int(verticalScale * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                
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
    let verticalScale: Double
    let comments: [Comment]
    let onSeek: (TimeInterval) -> Void
    
    @State private var selectedComment: Comment?
    @State private var commentToEdit: Comment?
    @State private var isScrubbing = false
    @State private var scrubbingTime: TimeInterval?
    @State private var dragStartTime: TimeInterval?
    
    // Pre-calculate expensive values to avoid recalculating in body
    private var playbackPosition: Double {
        guard duration > 0 else { return 0 }
        let timeToUse = isScrubbing ? (scrubbingTime ?? currentTime) : currentTime
        return timeToUse / duration
    }
    
    var body: some View {
        GeometryReader { geometry in
            let playheadX: CGFloat = 40 // Fixed position from left edge
            let numberOfBars = CGFloat(waveformData.leftSamples.count)
            // Total waveform width based on zoom
            let totalWaveformWidth = geometry.size.width * zoomLevel
            // Each bar gets equal space, no gaps
            let barWidth = totalWaveformWidth / numberOfBars
            let scrollOffset = playbackPosition * totalWaveformWidth
            
            // Debug logging every 5 seconds
            let _ = {
                if Int(currentTime) % 5 == 0 && currentTime > 0 && currentTime.truncatingRemainder(dividingBy: 1.0) < 0.02 {
                    print("🔍 Waveform Debug:")
                    print("   Time: \(String(format: "%.2f", currentTime))s / \(String(format: "%.2f", duration))s")
                    print("   Playback position: \(String(format: "%.3f", playbackPosition)) (\(String(format: "%.1f", playbackPosition * 100))%)")
                    print("   Zoom level: \(String(format: "%.1f", zoomLevel))x")
                    print("   View width: \(Int(geometry.size.width))px")
                    print("   Bar count: \(Int(numberOfBars)), Bar width: \(String(format: "%.2f", barWidth))px")
                    print("   Total waveform width: \(Int(totalWaveformWidth))px")
                    print("   Scroll offset: \(Int(scrollOffset))px")
                    print("   Playhead X: \(Int(playheadX))px")
                }
            }()
            
            ZStack(alignment: .leading) {
                // Dual waveform display (L/R channels)
                VStack(spacing: 0) {
                    // Left channel (top half) - extends down from center
                    ZStack(alignment: .bottom) {
                        Color.clear
                        HStack(spacing: 0) {
                            ForEach(Array(waveformData.leftSamples.enumerated()), id: \.offset) { index, sample in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(waveformBarColor(for: index, totalBars: waveformData.leftSamples.count))
                                    .frame(
                                        width: barWidth,
                                        height: max(2, CGFloat(sample) * (geometry.size.height / 2) * verticalScale)
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
                        HStack(spacing: 0) {
                            ForEach(Array(waveformData.rightSamples.enumerated()), id: \.offset) { index, sample in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(waveformBarColor(for: index, totalBars: waveformData.rightSamples.count))
                                    .frame(
                                        width: barWidth,
                                        height: max(2, CGFloat(sample) * (geometry.size.height / 2) * verticalScale)
                                    )
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(height: geometry.size.height / 2)
                }
                .frame(width: totalWaveformWidth, height: geometry.size.height, alignment: .leading)
                .offset(x: playheadX - scrollOffset)
                
                // Comment markers
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                    let commentPosition = (comment.timestamp / max(duration, 0.001)) * totalWaveformWidth
                    let (verticalOffset, colorIndex) = calculateCommentOffset(for: comment, at: index, in: comments)
                    CommentMarkerView(
                        comment: comment,
                        duration: duration,
                        isSelected: selectedComment?.id == comment.id,
                        colorIndex: colorIndex
                    )
                    .offset(x: playheadX + (commentPosition - scrollOffset), y: verticalOffset)
                    .onTapGesture {
                        #if os(iOS)
                        // On iOS, single tap opens the comment
                        commentToEdit = comment
                        #else
                        // On macOS, single click just selects and seeks
                        selectedComment = comment
                        onSeek(comment.timestamp)
                        #endif
                    }
                    #if os(macOS)
                    .onTapGesture(count: 2) {
                        // On macOS, double-click opens the comment
                        commentToEdit = comment
                    }
                    .contextMenu {
                        Button {
                            commentToEdit = comment
                        } label: {
                            Label("Edit Comment", systemImage: "pencil")
                        }
                        
                        Button {
                            onSeek(comment.timestamp)
                        } label: {
                            Label("Jump to Time", systemImage: "play.circle")
                        }
                    }
                    #endif
                }
                
                // Fixed playhead at left edge
                Rectangle()
                    .fill(isScrubbing ? Color.orange : Color.blue)
                    .frame(width: isScrubbing ? 4 : 3)
                    .shadow(color: .black.opacity(0.5), radius: isScrubbing ? 6 : 4, x: 0, y: 0)
                    .position(x: playheadX, y: geometry.size.height / 2)
                    .animation(.easeInOut(duration: 0.15), value: isScrubbing)
                    .zIndex(100)
                
                // Scrubbing time indicator
                if isScrubbing, let scrubTime = scrubbingTime {
                    VStack {
                        Text(formatTime(scrubTime))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            )
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    .zIndex(101)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !isScrubbing {
                            // Starting new drag
                            isScrubbing = true
                            dragStartTime = currentTime
                        }
                        
                        guard let startTime = dragStartTime else { return }
                        
                        // Simple approach: drag distance directly maps to time
                        // Dragging right = moving forward in time
                        // Dragging left = moving backward in time
                        let dragDistance = value.translation.width
                        
                        // Scale factor: how much time per pixel of drag
                        // At 1x zoom, totalWaveformWidth represents the full duration
                        let timePerPixel = duration / totalWaveformWidth
                        let timeChange = dragDistance * timePerPixel
                        
                        let newTime = startTime + timeChange
                        let clampedTime = max(0, min(duration, newTime))
                        
                        scrubbingTime = clampedTime
                    }
                    .onEnded { _ in
                        // Seek to the scrubbed position
                        if let time = scrubbingTime {
                            onSeek(time)
                        }
                        isScrubbing = false
                        scrubbingTime = nil
                        dragStartTime = nil
                    }
            )
        }
        .sheet(item: $commentToEdit) { comment in
            CommentDetailSheet(comment: comment, onSeek: onSeek)
        }
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    /// Calculate vertical offset and color index for overlapping comments
    private func calculateCommentOffset(for comment: Comment, at index: Int, in comments: [Comment]) -> (verticalOffset: CGFloat, colorIndex: Int) {
        // Find comments that are within 2 seconds of this comment
        let nearbyComments = comments.filter { otherComment in
            guard otherComment.id != comment.id else { return false }
            return abs(otherComment.timestamp - comment.timestamp) < 2.0
        }
        
        if nearbyComments.isEmpty {
            return (0, 0) // No offset needed, use default color
        }
        
        // Sort all nearby comments (including this one) by timestamp, then by ID for stability
        var allNearby = nearbyComments + [comment]
        allNearby.sort { first, second in
            if first.timestamp == second.timestamp {
                return first.id.uuidString < second.id.uuidString
            }
            return first.timestamp < second.timestamp
        }
        
        // Find this comment's index in the nearby group
        guard let position = allNearby.firstIndex(where: { $0.id == comment.id }) else {
            return (0, 0)
        }
        
        // Stagger vertically and assign different colors
        let verticalOffset = CGFloat(position) * 25.0 // Offset by 25 points each
        let colorIndex = position % 6 // Cycle through 6 colors
        
        return (verticalOffset, colorIndex)
    }
}

struct CommentMarkerView: View {
    let comment: Comment
    let duration: TimeInterval
    let isSelected: Bool
    let colorIndex: Int
    
    private var markerColor: Color {
        if isSelected {
            return .orange
        }
        
        // Color palette for overlapping comments
        switch colorIndex {
        case 0: return .yellow
        case 1: return .green
        case 2: return .cyan
        case 3: return .pink
        case 4: return .purple
        case 5: return .mint
        default: return .yellow
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Comment preview card (positioned above the line)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: comment.resolvedVoiceNoteURL != nil ? "mic.fill" : "text.bubble.fill")
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
                    .fill(markerColor.opacity(0.9))
            )
            .frame(width: 120)
            .shadow(radius: 2)
            .offset(x: -60) // Center the card so the line below is at the exact position
            
            // Marker line (this is at the exact timestamp position)
            Rectangle()
                .fill(markerColor)
                .frame(width: 3)
                .opacity(0.8)
        }
        .frame(height: 100, alignment: .top)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
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
