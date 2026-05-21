//
//  ShareProjectSheet.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import SwiftUI

struct ShareProjectSheet: View {
    let project: Project
    
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedConfirmation = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                
                // Title
                VStack(spacing: 8) {
                    Text("Share Project")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                // Share code display
                if let shareCode = project.shareCode {
                    VStack(spacing: 16) {
                        Text("Share Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 4) {
                            ForEach(Array(shareCode.enumerated()), id: \.offset) { index, char in
                                Text(String(char))
                                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(width: 50, height: 70)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                    )
                            }
                        }
                        
                        Button {
                            copyShareCode()
                        } label: {
                            HStack {
                                Image(systemName: showCopiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                Text(showCopiedConfirmation ? "Copied!" : "Copy Code")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(showCopiedConfirmation ? Color.green : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .animation(.easeInOut, value: showCopiedConfirmation)
                    }
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generating share code...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to share:")
                        .font(.headline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Copy the code above")
                    }
                    .font(.subheadline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("Send it to your client via email or message")
                    }
                    .font(.subheadline)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("They enter the code in Approvl to access the project")
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Share Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    private func copyShareCode() {
        guard let shareCode = project.shareCode else { return }
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareCode, forType: .string)
        #else
        UIPasteboard.general.string = shareCode
        #endif
        
        showCopiedConfirmation = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedConfirmation = false
        }
    }
}

#Preview {
    ShareProjectSheet(project: Project(
        name: "Test Project",
        clientName: "Test Client",
        ownerUserID: "user1",
        shareCode: "XY3K9P"
    ))
}
