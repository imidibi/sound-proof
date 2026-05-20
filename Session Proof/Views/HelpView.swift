//
//  HelpView.swift
//  Session Proof
//
//  Created by Ian Miller
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Overview Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overview")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Approvl is a mix distribution and approval system for music producers and studios. It allows you to create projects, which then can contain multiple songs, and each song can then have one or more mixes.")
                            .font(.body)
                    }

                    Divider()

                    // Getting Started Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Getting Started")
                            .font(.title2)
                            .fontWeight(.bold)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("For Producers")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                    Text("Create a new project")
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                    Text("Add songs to your project")
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                    Text("Upload mixes for each song")
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("4.")
                                    Text("Invite approvers to review your work")
                                }
                            }
                            .font(.body)
                        }
                    }

                    Divider()

                    // Approvers Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Approvers/Artists")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("A producer can add one or more approvers to the project. A \"key\" approver can also be optionally identified who has the override decision making ability where there are multiple approvers or commenters, for example in a band.")
                            .font(.body)

                        Text("Approvers are invited via email to download the app and create an account. Once they do, any projects they are associated with will download into their device, from where they can audition the mixes, and comment.")
                            .font(.body)
                    }

                    Divider()

                    // Syncing Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Syncing")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("The app runs on Mac, iPhone and iPad and a user's projects will sync across their devices. The sync process happens on app startup but can also be triggered by pressing the manual sync button that can be found in settings.")
                            .font(.body)
                    }

                    Divider()

                    // Support Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Support")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("For additional support or to report any bugs, please email:")
                            .font(.body)

                        Button {
                            if let url = URL(string: "mailto:support@studioguru.net?subject=Approvl%20Support") {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #elseif os(macOS)
                                NSWorkspace.shared.open(url)
                                #endif
                            }
                        } label: {
                            Text("support@studioguru.net")
                                .font(.body)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Approvl Help")
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
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 700)
        #endif
    }
}

#Preview {
    HelpView()
}
