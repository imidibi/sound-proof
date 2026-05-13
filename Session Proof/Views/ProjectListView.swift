//
//  ProjectListView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/8/26.
//

import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(SyncQueueService.self) private var syncQueueService
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var selectedMix: Mix?
    @State private var selectedSongForMenu: Song?
    @State private var selectedProjectForMenu: Project?
    @State private var showingNewProjectSheet = false
    @State private var showingNewSongSheet = false
    @State private var showingImportMixSheet = false
    @State private var showingJoinProjectSheet = false
    @State private var showingSettings = false
    @State private var expandedProjects: Set<UUID> = []
    @State private var expandedSongs: Set<UUID> = []
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedMix) {
                Section("Active Projects") {
                    ForEach(projects.filter { $0.status != .archived }) { project in
                        ProjectFolderRow(
                            project: project,
                            isExpanded: expandedProjects.contains(project.id),
                            expandedSongs: $expandedSongs,
                            selectedMix: $selectedMix,
                            selectedProjectForMenu: $selectedProjectForMenu,
                            selectedSongForMenu: $selectedSongForMenu,
                            onToggleExpand: {
                                if expandedProjects.contains(project.id) {
                                    expandedProjects.remove(project.id)
                                } else {
                                    expandedProjects.insert(project.id)
                                }
                            }
                        )
                        
                        // Expanded songs as direct List children for swipe actions
                        if expandedProjects.contains(project.id) {
                            ForEach(project.songs.sorted { $0.sortOrder < $1.sortOrder }) { song in
                                SongFolderRow(
                                    song: song,
                                    isExpanded: expandedSongs.contains(song.id),
                                    selectedMix: $selectedMix,
                                    selectedProjectForMenu: $selectedProjectForMenu,
                                    selectedSongForMenu: $selectedSongForMenu,
                                    onToggleExpand: {
                                        if expandedSongs.contains(song.id) {
                                            expandedSongs.remove(song.id)
                                        } else {
                                            expandedSongs.insert(song.id)
                                        }
                                    }
                                )
                                .padding(.leading, 32)
                                
                                // Expanded mixes as direct List children for swipe actions
                                if expandedSongs.contains(song.id) {
                                    ForEach(song.mixes.sorted { $0.versionNumber < $1.versionNumber }) { mix in
                                        MixRow(mix: mix, isSelected: selectedMix?.id == mix.id, onSelect: {
                                            selectedMix = mix
                                        })
                                        .padding(.leading, 64)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !projects.filter({ $0.status == .archived }).isEmpty {
                    Section("Archived") {
                        ForEach(projects.filter { $0.status == .archived }) { project in
                            ProjectFolderRow(
                                project: project,
                                isExpanded: expandedProjects.contains(project.id),
                                expandedSongs: $expandedSongs,
                                selectedMix: $selectedMix,
                                selectedProjectForMenu: $selectedProjectForMenu,
                                selectedSongForMenu: $selectedSongForMenu,
                                onToggleExpand: {
                                    if expandedProjects.contains(project.id) {
                                        expandedProjects.remove(project.id)
                                    } else {
                                        expandedProjects.insert(project.id)
                                    }
                                }
                            )
                            
                            // Expanded songs as direct List children for swipe actions
                            if expandedProjects.contains(project.id) {
                                ForEach(project.songs.sorted { $0.sortOrder < $1.sortOrder }) { song in
                                    SongFolderRow(
                                        song: song,
                                        isExpanded: expandedSongs.contains(song.id),
                                        selectedMix: $selectedMix,
                                        selectedProjectForMenu: $selectedProjectForMenu,
                                        selectedSongForMenu: $selectedSongForMenu,
                                        onToggleExpand: {
                                            if expandedSongs.contains(song.id) {
                                                expandedSongs.remove(song.id)
                                            } else {
                                                expandedSongs.insert(song.id)
                                            }
                                        }
                                    )
                                    .padding(.leading, 32)
                                    
                                    // Expanded mixes as direct List children for swipe actions
                                    if expandedSongs.contains(song.id) {
                                        ForEach(song.mixes.sorted { $0.versionNumber < $1.versionNumber }) { mix in
                                            MixRow(mix: mix, isSelected: selectedMix?.id == mix.id, onSelect: {
                                                selectedMix = mix
                                            })
                                            .padding(.leading, 64)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            #endif
            .navigationTitle("Sound Proof")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Always show New Project
                        Button {
                            showingNewProjectSheet = true
                        } label: {
                            Label("New Project", systemImage: "folder.badge.plus")
                        }
                        
                        // Show Join Project for clients
                        if authService.currentUser?.role == .client {
                            Button {
                                showingJoinProjectSheet = true
                            } label: {
                                Label("Join Project", systemImage: "link")
                            }
                        }
                        
                        // Context-aware options based on selection
                        if let selectedProject = selectedProjectForMenu {
                            Divider()
                            Button {
                                showingNewSongSheet = true
                            } label: {
                                Label("Add Song to \(selectedProject.name)", systemImage: "music.note")
                            }
                        }
                        
                        if let selectedSong = selectedSongForMenu {
                            Divider()
                            Button {
                                showingImportMixSheet = true
                            } label: {
                                Label("Import Mix to \(selectedSong.name)", systemImage: "square.and.arrow.down")
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                
                // Sync status indicator
                ToolbarItem(placement: .status) {
                    HStack(spacing: 8) {
                        // Network status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(networkMonitor.isConnected ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(networkMonitor.isConnected ? "Online" : "Offline")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Pending sync count
                        if syncQueueService.pendingSyncCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("\(syncQueueService.pendingSyncCount) pending")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectSheet()
            }
            .sheet(isPresented: $showingNewSongSheet) {
                if let project = selectedProjectForMenu {
                    NewSongSheet(project: project)
                }
            }
            .sheet(isPresented: $showingImportMixSheet) {
                if let song = selectedSongForMenu {
                    ImportMixSheet(song: song)
                }
            }
            .sheet(isPresented: $showingJoinProjectSheet) {
                JoinProjectSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        } detail: {
            if let mix = selectedMix {
                MixDetailView(mix: mix)
            } else if projects.isEmpty {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "Welcome to Sound Proof",
                        systemImage: "waveform.circle",
                        description: Text("Get started by creating a project")
                    )
                    
                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Label("Create Project", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "No Mix Selected",
                        systemImage: "waveform",
                        description: Text("Click on a project or song, then use the + button to add content")
                    )
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Start:")
                            .font(.headline)
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                            Text("Click a **project name** → Use + button to **Add Song**")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                            Text("Click a **song name** → Use + button to **Import Mix**")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
    }
}

struct ProjectFolderRow: View {
    @Bindable var project: Project
    let isExpanded: Bool
    @Binding var expandedSongs: Set<UUID>
    @Binding var selectedMix: Mix?
    @Binding var selectedProjectForMenu: Project?
    @Binding var selectedSongForMenu: Song?
    let onToggleExpand: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @State private var showingNewSongSheet = false
    @State private var showingShareSheet = false
    @State private var isEditingName = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool
    
    var canDelete: Bool {
        authService.currentUser?.role == .producer
    }
    
    var sortedSongs: [Song] {
        project.songs.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var isSelected: Bool {
        selectedProjectForMenu?.id == project.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project row
            HStack {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    if isEditingName {
                        TextField("Project Name", text: $project.name)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                isEditingName = false
                            }
                    } else {
                        Text(project.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    if let clientName = project.clientName {
                        Text(clientName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Share code indicator
                if let shareCode = project.shareCode {
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(shareCode)
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                
                if project.status != .draft {
                    StatusBadge(status: project.status)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                // Select this project for menu actions
                selectedProjectForMenu = project
                selectedSongForMenu = nil
                onToggleExpand()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDelete {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .contextMenu {
                if project.shareCode != nil {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share Project", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                }
                
                Button {
                    isEditingName = true
                    isNameFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Divider()
                
                Button {
                    selectedProjectForMenu = project
                    selectedSongForMenu = nil
                    showingNewSongSheet = true
                } label: {
                    Label("Add Song", systemImage: "music.note")
                }
                
                if canDelete {
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewSongSheet) {
            NewSongSheet(project: project)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareProjectSheet(project: project)
        }
        .confirmationDialog(
            "Delete Project",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(project.name)\"? This will also delete all songs and mixes in this project. This action cannot be undone.")
        }
    }
    
    private func deleteProject() {
        modelContext.delete(project)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting project: \(error)")
        }
    }
}

struct SongFolderRow: View {
    @Bindable var song: Song
    let isExpanded: Bool
    @Binding var selectedMix: Mix?
    @Binding var selectedProjectForMenu: Project?
    @Binding var selectedSongForMenu: Song?
    let onToggleExpand: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @State private var showingImportSheet = false
    @State private var isEditingName = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool
    
    var canDelete: Bool {
        authService.currentUser?.role == .producer
    }
    
    var sortedMixes: [Mix] {
        song.mixes.sorted { $0.versionNumber < $1.versionNumber }
    }
    
    var isSelected: Bool {
        selectedSongForMenu?.id == song.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Song row
            HStack {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
                    .font(.title3)
                
                if isEditingName {
                    TextField("Song Name", text: $song.name)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .fontWeight(.medium)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            isEditingName = false
                        }
                } else {
                    Text(song.name)
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Text("\(song.mixes.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                // Select this song for menu actions
                selectedSongForMenu = song
                selectedProjectForMenu = nil
                onToggleExpand()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDelete {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .contextMenu {
                Button {
                    isEditingName = true
                    isNameFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Divider()
                
                Button {
                    selectedSongForMenu = song
                    selectedProjectForMenu = nil
                    showingImportSheet = true
                } label: {
                    Label("Import Mix", systemImage: "square.and.arrow.down")
                }
                
                if canDelete {
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Song", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportMixSheet(song: song)
        }
        .confirmationDialog(
            "Delete Song",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSong()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(song.name)\"? This will also delete all mixes in this song. This action cannot be undone.")
        }
    }
    
    private func deleteSong() {
        modelContext.delete(song)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting song: \(error)")
        }
    }
}

struct MixRow: View {
    @Bindable var mix: Mix
    let isSelected: Bool
    let onSelect: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @State private var isEditingName = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool
    
    var canDelete: Bool {
        authService.currentUser?.role == .producer
    }
    
    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    TextField("Mix Name", text: $mix.name)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            isEditingName = false
                        }
                } else {
                    Text(mix.name)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                
                if let notes = mix.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            MixStatusBadge(status: mix.approvalStatus)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .tag(mix)
        .contextMenu {
            Button {
                isEditingName = true
                isNameFieldFocused = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            if canDelete {
                Divider()
                
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Mix", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete Mix",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteMix()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(mix.name)\"? This action cannot be undone.")
        }
    }
    
    private func deleteMix() {
        modelContext.delete(mix)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting mix: \(error)")
        }
    }
}

struct MixStatusBadge: View {
    let status: MixStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusEmoji)
                .font(.caption)
        }
    }

    private var statusColor: Color {
        switch status {
        case .draft: return .gray
        case .shared: return .blue
        case .inReview: return .orange
        case .approved: return .green
        case .superseded: return .secondary
        }
    }

    private var statusEmoji: String {
        switch status {
        case .draft: return "📝"
        case .shared: return "📤"
        case .inReview: return "👀"
        case .approved: return "✅"
        case .superseded: return "⏭️"
        }
    }
}

struct StatusBadge: View {
    let status: ProjectStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch status {
        case .draft: return .gray
        case .inReview: return .blue
        case .revisionsNeeded: return .orange
        case .approved: return .green
        case .archived: return .secondary
        }
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
}
