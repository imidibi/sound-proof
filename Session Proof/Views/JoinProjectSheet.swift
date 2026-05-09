//
//  JoinProjectSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import SwiftUI
import SwiftData

struct JoinProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSyncService.self) private var syncService
    
    @State private var shareCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                
                // Title
                VStack(spacing: 8) {
                    Text("Join Project")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Enter the share code from your producer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Share code input
                VStack(spacing: 16) {
                    Text("Share Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    TextField("ABC123", text: $shareCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .autocorrectionDisabled()
                        .frame(height: 70)
                        .padding(.horizontal)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        )
                        .padding(.horizontal)
                    
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Button {
                        Task {
                            await joinProject()
                        }
                    } label: {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Join Project")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(shareCode.count == 6 ? Color.green : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(shareCode.count != 6 || isJoining)
                    .padding(.horizontal)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How it works:")
                        .font(.headline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Producer shares a 6-character code with you")
                    }
                    .font(.subheadline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("Enter the code above")
                    }
                    .font(.subheadline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("You'll get access to all mixes and can leave comments")
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Join Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    private func joinProject() async {
        errorMessage = nil
        isJoining = true
        
        let code = shareCode.uppercased().trimmingCharacters(in: .whitespaces)
        
        do {
            let _ = try await syncService.joinProjectByShareCode(
                shareCode: code,
                modelContext: modelContext
            )
            
            await MainActor.run {
                isJoining = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isJoining = false
            }
        }
    }
}

#Preview {
    JoinProjectSheet()
        .environment(ProjectSyncService(
            firestoreService: FirestoreService(),
            cloudStorageService: CloudStorageService(),
            authService: AuthenticationService()
        ))
        .modelContainer(for: Project.self, inMemory: true)
}
