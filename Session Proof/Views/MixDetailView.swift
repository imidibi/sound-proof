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
                        Image(systemName: showingInspector ? "sidebar.right.fill" : "sidebar.right")
                            .font(.title3)
                            .foregroundStyle(showingInspector ? .blue : .secondary)
                            .contentShape(Rectangle())
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
        ZStack {
            VStack(spacing: 0) {
                // Mix header for iPad
                if UIDevice.current.userInterfaceIdiom == .pad {
                    MixHeaderView(mix: mix)
                        .padding()
                    Divider()
                }
                
                WaveformPlayerView(
                    mix: mix,
                    audioPlayerService: audioPlayerService
                )
            }
            
            // Floating comment button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Inspector button (iPhone and iPad)
                        Button {
                            showingInspector = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        
                        // Add comment button
                        Button {
                            showingCommentSheet = true
                        } label: {
                            Image(systemName: "plus.message.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }
                    .padding()
                }
            }
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
              let mixId = mix.firestoreId else {
            print("📝 Mix not part of synced project - comment sync disabled")
            return
        }
        
        print("🔄 Starting real-time comment sync for mix: \(mix.name)")
        
        await MainActor.run {
            commentListener = syncService.startListeningToComments(
                projectId: projectId,
                mixId: mixId,
                mix: mix,
                modelContext: modelContext
            )
            
            // Also start listening for reviewer changes
            print("🔄 Starting real-time reviewer sync for project: \(project.name)")
            reviewerListener = syncService.startListeningToReviewers(
                projectId: projectId,
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
        print("⏹️ Stopped comment and reviewer sync")
    }
}

struct MixHeaderView: View {
    @Bindable var mix: Mix
    
    @State private var isEditingMixName = false
    @State private var isEditingSongName = false
    @FocusState private var mixNameFocused: Bool
    @FocusState private var songNameFocused: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let song = mix.song {
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
                            isEditingSongName = false
                        }
                    } else {
                        Text(song.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
                
                HStack {
                    if isEditingMixName {
                        TextField("Mix Name", text: $mix.name)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .focused($mixNameFocused)
                            .onSubmit {
                                isEditingMixName = false
                            }
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
