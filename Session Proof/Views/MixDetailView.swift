//
//  MixDetailView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct MixDetailView: View {
    @Bindable var mix: Mix
    @State private var audioPlayerService = AudioPlayerService()
    @State private var showingCommentSheet = false
    @State private var showingInspector = false
    @State private var commentListener: ListenerRegistration?
    @State private var reviewerListener: ListenerRegistration?
    @State private var approvalListener: ListenerRegistration?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectSyncService.self) private var syncService
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .task(id: mix.id) {
            await startCommentSync()
        }
        .onDisappear {
            stopCommentSync()
        }
    }
    
    #if os(macOS)
    private var macOSLayout: some View {
        ZStack(alignment: .trailing) {
            // Main waveform area - always full width
            VStack(spacing: 0) {
                // Mix info header with inspector toggle
                HStack {
                    MixHeaderView(mix: mix)
                        .padding()
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingInspector.toggle()
                        }
                    } label: {
                        // Use sidebar.right on macOS (sidebar.right.fill not available)
                        Image(systemName: "sidebar.right")
                            .font(.title3)
                            .foregroundStyle(showingInspector ? .blue : .secondary)
                            .contentShape(Rectangle())
                            .symbolVariant(showingInspector ? .fill : .none)
                    }
                    .buttonStyle(.plain)
                    .help(showingInspector ? "Hide Inspector (Cmd+I)" : "Show Inspector (Cmd+I)")
                    .keyboardShortcut("i", modifiers: .command)
                    .padding()
                    
                    // Spacer to account for inspector overlay
                    if showingInspector {
                        Spacer()
                            .frame(width: 300)
                    }
                }
                .zIndex(10)
                
                Divider()
                
                // Waveform and player
                WaveformPlayerView(
                    mix: mix,
                    audioPlayerService: audioPlayerService,
                    inspectorWidth: showingInspector ? 300 : 0
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating inspector overlay on the right
            if showingInspector {
                VStack(spacing: 0) {
                    Divider()
                    
                    MixInspectorView(
                        mix: mix,
                        audioPlayerService: audioPlayerService,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingInspector = false
                            }
                        }
                    )
                }
                .frame(width: 300)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .trailing))
                .zIndex(20)
            }
        }
    }
    #endif
    
    #if os(iOS)
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            // Compact header for both iPad and iPhone
            HStack {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad: full header with mix info
                    MixHeaderView(mix: mix)
                } else {
                    // iPhone: just format info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mix.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(formatDuration(mix.duration))
                                .font(.caption)
                                .monospacedDigit()
                            
                            Text("•")
                                .font(.caption)
                            
                            Text("\(Int(mix.sampleRate / 1000))kHz • \(mix.channels)ch")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Action buttons - horizontal for both devices
                HStack(spacing: 12) {
                    Button {
                        showingInspector = true
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(UIDevice.current.userInterfaceIdiom == .pad ? .title2 : .title3)
                            .foregroundStyle(.white)
                            .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 38, 
                                   height: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 38)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    
                    Button {
                        showingCommentSheet = true
                    } label: {
                        Image(systemName: "plus.message.fill")
                            .font(UIDevice.current.userInterfaceIdiom == .pad ? .title2 : .title3)
                            .foregroundStyle(.white)
                            .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 38, 
                                   height: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 38)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                }
            }
            .padding()
            
            Divider()
            
            WaveformPlayerView(
                mix: mix,
                audioPlayerService: audioPlayerService
            )
        }
        .navigationTitle(mix.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCommentSheet) {
            NewCommentSheet(mix: mix, timestamp: audioPlayerService.currentTime)
        }
        .sheet(isPresented: $showingInspector) {
            NavigationStack {
                MixInspectorView(mix: mix, audioPlayerService: audioPlayerService)
                    .navigationTitle("Inspector")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingInspector = false
                            }
                        }
                    }
            }
        }
    }
    #endif
    
    private func startCommentSync() async {
        // Only start syncing if this mix is part of a synced project
        guard let song = mix.song,
              let project = song.project,
              let projectId = project.firestoreId,
              let songId = song.firestoreId,
              let mixId = mix.firestoreId else {
            print("📝 Mix not part of synced project - sync disabled")
            return
        }
        
        print("🔄 Starting real-time sync for mix: \(mix.name)")
        
        await MainActor.run {
            // Start listening for comments
            commentListener = syncService.startListeningToComments(
                projectId: projectId,
                mixId: mixId,
                mix: mix,
                modelContext: modelContext
            )
            
            // Start listening for reviewer changes
            print("🔄 Starting real-time reviewer sync for project: \(project.name)")
            reviewerListener = syncService.startListeningToReviewers(
                projectId: projectId,
                project: project,
                modelContext: modelContext
            )
            
            // Start listening for approval changes
            print("🔄 Starting real-time approval sync for mix: \(mix.name)")
            approvalListener = syncService.startListeningToApprovals(
                projectId: projectId,
                songId: songId,
                mixId: mixId,
                mix: mix,
                project: project,
                modelContext: modelContext
            )
        }
    }
    
    private func stopCommentSync() {
        commentListener?.remove()
        commentListener = nil
        reviewerListener?.remove()
        reviewerListener = nil
        approvalListener?.remove()
        approvalListener = nil
        print("⏹️ Stopped all real-time sync")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MixHeaderView: View {
    @Bindable var mix: Mix
    
    @State private var isEditingMixName = false
    @State private var isEditingSongName = false
    @FocusState private var mixNameFocused: Bool
    @FocusState private var songNameFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(FirestoreService.self) private var firestoreService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let song = mix.song {
                    HStack {
                        if isEditingSongName {
                            TextField("Song Name", text: Binding(
                                get: { song.name },
                                set: { song.name = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .focused($songNameFocused)
                            .onSubmit {
                                syncSongName()
                            }
                            .onChange(of: songNameFocused) { oldValue, newValue in
                                // When focus is lost, save the changes
                                if oldValue && !newValue {
                                    syncSongName()
                                }
                            }
                            
                            Button {
                                syncSongName()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(song.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                HStack {
                    if isEditingMixName {
                        TextField("Mix Name", text: $mix.name)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .focused($mixNameFocused)
                            .onSubmit {
                                syncMixName()
                            }
                            .onChange(of: mixNameFocused) { oldValue, newValue in
                                // When focus is lost, save the changes
                                if oldValue && !newValue {
                                    syncMixName()
                                }
                            }
                        
                        Button {
                            syncMixName()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(mix.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    MixStatusBadge(status: mix.approvalStatus)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(mix.duration))
                    .font(.subheadline)
                    .monospacedDigit()
                
                Text("\(Int(mix.sampleRate / 1000))kHz • \(mix.channels)ch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if mix.song != nil {
                Button {
                    isEditingSongName = true
                    songNameFocused = true
                } label: {
                    Label("Rename Song", systemImage: "music.note")
                }
            }
            
            Button {
                isEditingMixName = true
                mixNameFocused = true
            } label: {
                Label("Rename Mix", systemImage: "waveform")
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func syncSongName() {
        guard let song = mix.song else { return }
        isEditingSongName = false
        
        do {
            try modelContext.save()
            Logger.debug("✅ Song name updated locally: \(song.name)")
            
            // Sync to Firestore
            if let projectId = song.project?.firestoreId,
               let songId = song.firestoreId {
                Task {
                    do {
                        let data: [String: Any] = [
                            "name": song.name
                        ]
                        try await firestoreService.updateSong(projectId: projectId, songId: songId, data: data)
                        Logger.debug("✅ Song name synced to Firestore: \(song.name)")
                    } catch {
                        Logger.error("Error syncing song name to Firestore: \(error)")
                    }
                }
            }
        } catch {
            Logger.error("Error saving song name: \(error)")
        }
    }
    
    private func syncMixName() {
        isEditingMixName = false
        
        do {
            try modelContext.save()
            Logger.debug("✅ Mix name updated locally: \(mix.name)")
            
            // Sync to Firestore
            guard let song = mix.song,
                  let projectId = song.project?.firestoreId,
                  let songId = song.firestoreId,
                  let mixId = mix.firestoreId else {
                Logger.warning("⚠️ Cannot sync mix name - missing IDs")
                return
            }
            
            Task {
                do {
                    let data: [String: Any] = ["name": mix.name]
                    try await firestoreService.updateMix(projectId: projectId, songId: songId, mixId: mixId, data: data)
                    Logger.debug("✅ Mix name synced to Firestore: \(mix.name)")
                } catch {
                    Logger.error("Error syncing mix name to Firestore: \(error)")
                }
            }
        } catch {
            Logger.error("Error saving mix name: \(error)")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Mix.self, configurations: config)
    let context = container.mainContext
    
    let mix = Mix(name: "Mix V1", versionNumber: 1, duration: 180)
    context.insert(mix)
    
    return MixDetailView(mix: mix)
        .modelContainer(container)
}
