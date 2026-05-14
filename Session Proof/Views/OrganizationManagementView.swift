//
//  OrganizationManagementView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/14/26.
//

import SwiftUI
import SwiftData

struct OrganizationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @Query private var organizations: [Organization]
    
    @State private var showingNewOrganization = false
    @State private var selectedOrganization: Organization?
    
    var body: some View {
        NavigationStack {
            List {
                if organizations.isEmpty {
                    ContentUnavailableView(
                        "No Organization",
                        systemImage: "building.2",
                        description: Text("Create an organization to manage your studio and team members")
                    )
                } else {
                    ForEach(organizations) { organization in
                        Button {
                            selectedOrganization = organization
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(organization.name)
                                    .font(.headline)
                                
                                HStack {
                                    Label(organization.type.rawValue.capitalized, systemImage: "building.2")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    if !organization.isActive {
                                        Text("Inactive")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("\(organization.memberIds.count) members")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Organizations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewOrganization = true
                    } label: {
                        Label("New Organization", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewOrganization) {
                NewOrganizationSheet()
            }
            .sheet(item: $selectedOrganization) { organization in
                OrganizationDetailView(organization: organization)
            }
        }
    }
}

struct NewOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @State private var name = ""
    @State private var type: OrganizationType = .studio
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    @State private var country = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var maxProducers = 5
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Organization Name", text: $name)
                    
                    Picker("Type", selection: $type) {
                        Text("Studio").tag(OrganizationType.studio)
                        Text("Independent").tag(OrganizationType.independent)
                    }
                } header: {
                    Text("Basic Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Address", text: $address)
                    TextField("City", text: $city)
                    TextField("State", text: $state)
                    TextField("Zip Code", text: $zipCode)
                    TextField("Country", text: $country)
                } header: {
                    Text("Address")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                    TextField("Website", text: $website)
                } header: {
                    Text("Contact")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Stepper("Max Producers: \(maxProducers)", value: $maxProducers, in: 1...50)
                } header: {
                    Text("License")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Organization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createOrganization()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createOrganization() {
        let organization = Organization(
            name: name,
            type: type,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zipCode: zipCode.isEmpty ? nil : zipCode,
            country: country.isEmpty ? nil : country,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            website: website.isEmpty ? nil : website,
            maxProducers: maxProducers
        )
        
        // Add current user as a member
        if let userId = authService.currentUser?.id {
            organization.memberIds.append(userId)
        }
        
        modelContext.insert(organization)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating organization: \(error)")
        }
    }
}

struct OrganizationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    
    @Bindable var organization: Organization
    
    @State private var showingAddMember = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name", value: organization.name)
                    LabeledContent("Type", value: organization.type.rawValue.capitalized)
                    LabeledContent("Status", value: organization.isActive ? "Active" : "Inactive")
                } header: {
                    Text("Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if let address = organization.address, !address.isEmpty {
                    Section {
                        LabeledContent("Address", value: address)
                        if let city = organization.city {
                            LabeledContent("City", value: city)
                        }
                        if let state = organization.state {
                            LabeledContent("State", value: state)
                        }
                        if let zip = organization.zipCode {
                            LabeledContent("Zip", value: zip)
                        }
                        if let country = organization.country {
                            LabeledContent("Country", value: country)
                        }
                    } header: {
                        Text("Address")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                
                Section {
                    if let phone = organization.phone {
                        LabeledContent("Phone", value: phone)
                    }
                    if let email = organization.email {
                        LabeledContent("Email", value: email)
                    }
                    if let website = organization.website {
                        LabeledContent("Website", value: website)
                    }
                } header: {
                    Text("Contact")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    LabeledContent("Max Producers", value: "\(organization.maxProducers)")
                    LabeledContent("Current Members", value: "\(organization.memberIds.count)")
                } header: {
                    Text("License")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    ForEach(organization.memberIds, id: \.self) { memberId in
                        Text(memberId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Members")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Organization", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(organization.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete Organization",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteOrganization()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the organization. This action cannot be undone.")
            }
        }
    }
    
    private func deleteOrganization() {
        modelContext.delete(organization)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error deleting organization: \(error)")
        }
    }
}

#Preview {
    OrganizationManagementView()
        .modelContainer(for: Organization.self, inMemory: true)
}
