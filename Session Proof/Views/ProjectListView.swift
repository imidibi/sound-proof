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
    // DISABLED: Share code functionality removed - use email invitations only
    // @State private var showingJoinProjectSheet = false
    @State private var showingSettings = false
    @State private var expandedProjects: Set<UUID> = []
    @State private var expandedSongs: Set<UUID> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Display preferences
    @AppStorage("showArchivedProjects") private var showArchivedProjects = false
    @AppStorage("projectSortOrder") private var projectSortOrder = "lastActivity"
    
    // Notification deep link handling
    @State private var pendingNavigation: (projectId: String, mixId: String)?
    
    // Helper function to filter songs based on user role
    // Archived songs are hidden from non-producers
    private func visibleSongs(for project: Project) -> [Song] {
        let isProducer = authService.currentUser?.id == project.ownerUserID
        
        return project.songs
            .filter { song in
                // Show all songs to producer
                if isProducer {
                    return true
                }
                // Hide archived songs from non-producers
                return song.status != .archived
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var activeProjects: [Project] {
        let filtered = projects.filter { $0.status != .archived }
        
        // Apply sorting
        if projectSortOrder == "alphabetical" {
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            // Default: lastActivity (already sorted by updatedAt from @Query)
            return filtered
        }
    }
    
    private var archivedProjects: [Project] {
        let filtered = projects.filter { $0.status == .archived }
        
        // Apply sorting
        if projectSortOrder == "alphabetical" {
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            // Default: lastActivity
            return filtered
        }
    }
    
    private var shouldShowArchivedSection: Bool {
        // Only show archived section if:
        // 1. There are archived projects
        // 2. User is a producer (checked in the view)
        // 3. User has enabled the setting
        return !archivedProjects.isEmpty && showArchivedProjects
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedMix) {
                Section("Active Projects") {
                    ForEach(activeProjects) { project in
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
                            ForEach(visibleSongs(for: project)) { song in
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
                                    ForEach(song.mixes.filter { !$0.isDeleted }.sorted { $0.versionNumber < $1.versionNumber }) { mix in
                                        MixRow(mix: mix, isSelected: selectedMix?.id == mix.id, onSelect: {
                                            selectedMix = mix
                                        }, onDelete: {
                                            selectedMix = nil
                                        })
                                        .padding(.leading, 64)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if shouldShowArchivedSection {
                    Section("Archived") {
                        ForEach(archivedProjects) { project in
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
                                ForEach(visibleSongs(for: project)) { song in
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
                                        ForEach(song.mixes.filter { !$0.isDeleted }.sorted { $0.versionNumber < $1.versionNumber }) { mix in
                                            MixRow(mix: mix, isSelected: selectedMix?.id == mix.id, onSelect: {
                                                selectedMix = mix
                                            }, onDelete: {
                                                selectedMix = nil
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
            .navigationTitle("Approvl")
            .toolbar {
                #if os(macOS)
                // Mac-specific toolbar layout
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    
                    Menu {
                        // Always show New Project
                        Button {
                            showingNewProjectSheet = true
                        } label: {
                            Label("New Project", systemImage: "folder.badge.plus")
                        }
                        
                        // DISABLED: Share code functionality removed - use email invitations only
                        // Show Join Project for artists
                        // if authService.currentUser?.role == .artist {
                        //     Button {
                        //         showingJoinProjectSheet = true
                        //     } label: {
                        //         Label("Join Project", systemImage: "link")
                        //     }
                        // }
                        
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
                #else
                // iOS toolbar layout
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Always show New Project
                        Button {
                            showingNewProjectSheet = true
                        } label: {
                            Label("New Project", systemImage: "folder.badge.plus")
                        }
                        
                        // DISABLED: Share code functionality removed - use email invitations only
                        // Show Join Project for artists
                        // if authService.currentUser?.role == .artist {
                        //     Button {
                        //         showingJoinProjectSheet = true
                        //     } label: {
                        //         Label("Join Project", systemImage: "link")
                        //     }
                        // }
                        
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
                #endif
                
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
            // DISABLED: Share code functionality removed - use email invitations only
            // .sheet(isPresented: $showingJoinProjectSheet) {
            //     JoinProjectSheet()
            // }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        } detail: {
            if let mix = selectedMix {
                MixDetailView(mix: mix)
            } else if projects.isEmpty {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "Welcome to Approvl",
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
    @Environment(FirestoreService.self) private var firestoreService
    
    @State private var showingNewSongSheet = false
    @State private var showingEditProjectSheet = false
    @State private var showingReviewersSheet = false
    @State private var showingApprovalsStatus = false
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
                Button {
                    showingEditProjectSheet = true
                } label: {
                    Label("Edit Project", systemImage: "pencil")
                }
                
                Button {
                    isEditingName = true
                    isNameFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "text.cursor")
                }
                
                Button {
                    showingApprovalsStatus = true
                } label: {
                    Label("Approvals Status", systemImage: "checkmark.circle")
                }
                
                Divider()
                
                Button {
                    selectedProjectForMenu = project
                    selectedSongForMenu = nil
                    showingNewSongSheet = true
                } label: {
                    Label("Add Song", systemImage: "music.note")
                }
                
                Button {
                    showingReviewersSheet = true
                } label: {
                    Label("Manage Approvers", systemImage: "person.2")
                }
                
                if canDelete {
                    Divider()
                    
                    // Archive/Reload option
                    if project.status == .archived {
                        Button {
                            reloadProject()
                        } label: {
                            Label("Reload Project", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button {
                            archiveProject()
                        } label: {
                            Label("Archive Project", systemImage: "archivebox")
                        }
                    }
                    
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
        .sheet(isPresented: $showingEditProjectSheet) {
            ProjectEditSheet(project: project)
        }
        .sheet(isPresented: $showingReviewersSheet) {
            ProjectReviewersView(project: project)
        }
        .sheet(isPresented: $showingApprovalsStatus) {
            ApprovalsStatusView(project: project, selectedSong: nil)
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
    
    private func archiveProject() {
        project.status = .archived
        project.isArchived = true
        project.archivedAt = Date()
        
        do {
            try modelContext.save()
            print("✅ Project archived locally: \(project.name)")
            
            // Sync to Firestore
            if let projectId = project.firestoreId {
                Task {
                    do {
                        try await firestoreService.archiveProject(projectId: projectId)
                        print("✅ Project archive synced to Firestore")
                    } catch {
                        print("❌ Error syncing archive to Firestore: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error archiving project: \(error)")
        }
    }
    
    private func reloadProject() {
        project.status = .draft
        project.isArchived = false
        project.archivedAt = nil
        
        do {
            try modelContext.save()
            print("✅ Project reloaded locally: \(project.name)")
            
            // Sync to Firestore
            if let projectId = project.firestoreId {
                Task {
                    do {
                        try await firestoreService.reloadProject(projectId: projectId)
                        print("✅ Project reload synced to Firestore")
                    } catch {
                        print("❌ Error syncing reload to Firestore: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error reloading project: \(error)")
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
    @Environment(FirestoreService.self) private var firestoreService
    
    @State private var showingImportSheet = false
    @State private var showingApprovalsStatus = false
    @State private var isEditingName = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFieldFocused: Bool
    
    var canDelete: Bool {
        authService.currentUser?.role == .producer
    }
    
    var sortedMixes: [Mix] {
        song.mixes.filter { !$0.isDeleted }.sorted { $0.versionNumber < $1.versionNumber }
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
                
                Text("\(song.mixes.filter { !$0.isDeleted }.count)")
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
                
                Button {
                    showingApprovalsStatus = true
                } label: {
                    Label("Approvals Status", systemImage: "checkmark.circle")
                }
                
                if canDelete {
                    Divider()
                    
                    // Archive/Reload option
                    if song.status == .archived {
                        Button {
                            reloadSong()
                        } label: {
                            Label("Reload Song", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button {
                            archiveSong()
                        } label: {
                            Label("Archive Song", systemImage: "archivebox")
                        }
                    }
                    
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
        .sheet(isPresented: $showingApprovalsStatus) {
            if let project = song.project {
                ApprovalsStatusView(project: project, selectedSong: song)
            }
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
    
    private func archiveSong() {
        song.status = .archived
        song.isArchived = true
        song.archivedAt = Date()
        
        do {
            try modelContext.save()
            print("✅ Song archived locally: \(song.name)")
            
            // Sync to Firestore
            if let projectId = song.project?.firestoreId,
               let songId = song.firestoreId {
                Task {
                    do {
                        try await firestoreService.archiveSong(projectId: projectId, songId: songId)
                        print("✅ Song archive synced to Firestore")
                    } catch {
                        print("❌ Error syncing archive to Firestore: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error archiving song: \(error)")
        }
    }
    
    private func reloadSong() {
        song.status = .draft
        song.isArchived = false
        song.archivedAt = nil
        
        do {
            try modelContext.save()
            print("✅ Song reloaded locally: \(song.name)")
            
            // Sync to Firestore
            if let projectId = song.project?.firestoreId,
               let songId = song.firestoreId {
                Task {
                    do {
                        try await firestoreService.reloadSong(projectId: projectId, songId: songId)
                        print("✅ Song reload synced to Firestore")
                    } catch {
                        print("❌ Error syncing reload to Firestore: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error reloading song: \(error)")
        }
    }
}

struct MixRow: View {
    @Bindable var mix: Mix
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

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
        // Notify parent to clear selection if this mix is selected
        if isSelected {
            onDelete?()
        }

        // Use soft delete for cloud sync
        mix.isDeleted = true
        mix.needsUpload = true
        mix.lastModifiedAt = Date()

        do {
            try modelContext.save()
            print("✓ Mix marked for deletion and will sync to cloud")
        } catch {
            print("Error marking mix for deletion: \(error)")
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
