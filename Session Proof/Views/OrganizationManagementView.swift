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
    
    private var userOrganization: Organization? {
        guard let userId = authService.currentUser?.id else { return nil }
        return organizations.first { $0.memberIds.contains(userId) }
    }
    
    var body: some View {
        Group {
            if let organization = userOrganization {
                // Edit existing organization
                OrganizationEditView(organization: organization)
            } else {
                // Create new organization
                NewOrganizationSheet()
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
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600)
        #endif
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
            print("✅ Organization created: \(organization.name)")
            print("   Member IDs: \(organization.memberIds)")
            dismiss()
        } catch {
            print("❌ Error creating organization: \(error)")
        }
    }
}

struct OrganizationEditView: View {
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
                    TextField("Name", text: $organization.name)
                    
                    Picker("Type", selection: $organization.type) {
                        Text("Studio").tag(OrganizationType.studio)
                        Text("Independent").tag(OrganizationType.independent)
                    }
                    
                    Toggle("Active", isOn: $organization.isActive)
                } header: {
                    Text("Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Address", text: Binding(
                        get: { organization.address ?? "" },
                        set: { organization.address = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("City", text: Binding(
                        get: { organization.city ?? "" },
                        set: { organization.city = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("State", text: Binding(
                        get: { organization.state ?? "" },
                        set: { organization.state = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Zip Code", text: Binding(
                        get: { organization.zipCode ?? "" },
                        set: { organization.zipCode = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Country", text: Binding(
                        get: { organization.country ?? "" },
                        set: { organization.country = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Address")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    TextField("Phone", text: Binding(
                        get: { organization.phone ?? "" },
                        set: { organization.phone = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Email", text: Binding(
                        get: { organization.email ?? "" },
                        set: { organization.email = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Website", text: Binding(
                        get: { organization.website ?? "" },
                        set: { organization.website = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Contact")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Section {
                    Stepper("Max Producers: \(organization.maxProducers)", value: $organization.maxProducers, in: 1...50)
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
            .navigationTitle("Edit Organization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveOrganization()
                    }
                    .disabled(organization.name.isEmpty)
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
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600)
        #endif
    }
    
    private func saveOrganization() {
        organization.updatedAt = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving organization: \(error)")
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
