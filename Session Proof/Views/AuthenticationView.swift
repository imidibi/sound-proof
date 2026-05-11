//
//  AuthenticationView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import SwiftUI
import FirebaseCore

struct AuthenticationView: View {
    @State private var isSignUp = false
    @State private var showFirebaseStatus = false
    @State private var showDebugAlert = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if isSignUp {
                SignUpView(showSignIn: {
                    withAnimation {
                        isSignUp = false
                    }
                })
            } else {
                SignInView(showSignUp: {
                    withAnimation {
                        isSignUp = true
                    }
                })
            }
            
            // Firebase status indicator in top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFirebaseStatus.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(firebaseStatusColor)
                                .frame(width: 10, height: 10)
                            Text(firebaseStatusText)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.3))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                Spacer()
            }
        }
        .sheet(isPresented: $showFirebaseStatus) {
            FirebaseStatusView()
        }
    }
    
    private var firebaseStatusColor: Color {
        guard let app = FirebaseApp.app() else { return .red }
        let options = app.options
        guard let apiKey = options.apiKey, !apiKey.isEmpty else { return .red }
        return .green
    }
    
    private var firebaseStatusText: String {
        guard let app = FirebaseApp.app() else { return "Firebase Not Configured" }
        let options = app.options
        guard let apiKey = options.apiKey, !apiKey.isEmpty else { return "No API Key" }
        return "Firebase Ready"
    }
}

struct SignInView: View {
    @Environment(AuthenticationService.self) private var authService
    
    let showSignUp: () -> Void
    
    @State private var email = ""
    @State private var password = ""
    @State private var shareCode = ""
    @State private var showShareCodeEntry = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Logo and title
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                
                Text("Sound Proof")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Professional Audio Review")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
            
            // Sign in form
            VStack(spacing: 20) {
                if showShareCodeEntry {
                    shareCodeSection
                } else {
                    emailPasswordSection
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Toggle between sign in and share code
            Button {
                withAnimation {
                    showShareCodeEntry.toggle()
                    errorMessage = nil
                }
            } label: {
                Text(showShareCodeEntry ? "Sign in with email instead" : "Have a share code?")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 20)
        }
    }
    
    private var emailPasswordSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("email@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
            
            Button {
                Task {
                    await signIn()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(email.isEmpty || password.isEmpty || isLoading)
            
            Button("Create an account") {
                showSignUp()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
    
    private var shareCodeSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Project Share Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ABC123", text: $shareCode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.oneTimeCode)
                    .font(.system(.title3, design: .monospaced))
            }
            
            Text("Enter the 6-character code shared by the producer to access the project as a guest.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await joinWithShareCode()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Join Project")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(shareCode.isEmpty || isLoading)
        }
    }
    
    private func signIn() async {
        errorMessage = nil
        isLoading = true
        
        defer {
            isLoading = false
        }
        
        do {
            print("🔵 Attempting to sign in with email: \(email)")
            try await authService.signIn(email: email, password: password)
            print("✅ Sign in successful!")
            // Success - the view will automatically transition when currentUser is set
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
            print("❌ Sign in error: \(error)")
            print("❌ Error details: \(error)")
        }
    }
    
    private func joinWithShareCode() async {
        errorMessage = nil
        isLoading = true
        
        // TODO: Implement guest access with share code
        errorMessage = "Guest access coming soon! Please create an account for now."
        
        isLoading = false
    }
}

struct SignUpView: View {
    @Environment(AuthenticationService.self) private var authService
    
    let showSignIn: () -> Void
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var selectedRole: UserRole = .producer
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                // Logo and title
                VStack(spacing: 16) {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                    
                    Text("Create Account")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                // Sign up form
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Full Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("John Doe", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("email@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("I am a...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("Role", selection: $selectedRole) {
                            Label("Producer/Engineer", systemImage: "music.note.list")
                                .tag(UserRole.producer)
                            Label("Client/Reviewer", systemImage: "person.fill")
                                .tag(UserRole.client)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Button {
                        Task {
                            await signUp()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(!isFormValid || isLoading)
                    
                    Button("Already have an account? Sign in") {
                        showSignIn()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 20)
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !displayName.isEmpty &&
        password == confirmPassword &&
        password.count >= 6
    }
    
    private func signUp() async {
        errorMessage = nil
        isLoading = true
        
        defer {
            isLoading = false
        }
        
        do {
            print("🔵 Attempting to sign up with email: \(email)")
            try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName,
                role: selectedRole
            )
            print("✅ Sign up successful!")
            // Success - the view will automatically transition when currentUser is set
        } catch {
            errorMessage = "Sign up failed: \(error.localizedDescription)"
            print("❌ Sign up error: \(error)")
            print("❌ Error details: \(error)")
        }
    }
}

struct FirebaseStatusView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Firebase Configuration") {
                    StatusRow(
                        label: "Firebase App",
                        status: FirebaseApp.app() != nil,
                        detail: FirebaseApp.app() != nil ? "Configured" : "Not configured"
                    )
                    
                    if let app = FirebaseApp.app() {
                        let options = app.options
                        
                        StatusRow(
                            label: "API Key",
                            status: options.apiKey != nil && !(options.apiKey?.isEmpty ?? true),
                            detail: (options.apiKey == nil || options.apiKey!.isEmpty) ? "Missing" : "Present (\(options.apiKey!.prefix(10))...)"
                        )
                        
                        StatusRow(
                            label: "Project ID",
                            status: options.projectID != nil && !options.projectID!.isEmpty,
                            detail: options.projectID ?? "Missing"
                        )
                        
                        StatusRow(
                            label: "App ID",
                            status: !(options.googleAppID.isEmpty),
                            detail: options.googleAppID.isEmpty ? "Missing" : "Present"
                        )
                        
                        StatusRow(
                            label: "Storage Bucket",
                            status: options.storageBucket != nil && !options.storageBucket!.isEmpty,
                            detail: options.storageBucket ?? "Not configured"
                        )
                    }
                }
                
                Section("Required Services") {
                    ServiceRow(
                        name: "Authentication",
                        description: "Email/password sign-in must be enabled in Firebase Console",
                        icon: "person.circle"
                    )
                    
                    ServiceRow(
                        name: "Firestore Database",
                        description: "Must be created in Firebase Console",
                        icon: "externaldrive"
                    )
                    
                    ServiceRow(
                        name: "Cloud Storage",
                        description: "Must be enabled for audio file uploads",
                        icon: "cloud"
                    )
                }
                
                Section("Next Steps") {
                    VStack(alignment: .leading, spacing: 12) {
                        if FirebaseApp.app() == nil {
                            Text("⚠️ Firebase not configured")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text("The GoogleService-Info.plist file is missing or invalid. See FIREBASE_SETUP.md for instructions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let options = FirebaseApp.app()?.options, options.projectID == nil || options.projectID!.isEmpty {
                            Text("⚠️ Incomplete configuration")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text("Firebase is initialized but missing project ID. Check your GoogleService-Info.plist file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("✓ Configuration looks good")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("Firebase SDK is configured. Make sure to enable Authentication, Firestore, and Storage in the Firebase Console.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Test Connection") {
                    Text("Try creating an account to test if Firebase Authentication is working. If you get network errors, check that:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Email/Password auth is enabled in Firebase Console", systemImage: "checkmark.circle")
                        Label("Your Mac has internet connection", systemImage: "checkmark.circle")
                        Label("The app has network entitlements", systemImage: "checkmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Firebase Status")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

struct StatusRow: View {
    let label: String
    let status: Bool
    let detail: String
    
    var body: some View {
        HStack {
            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ServiceRow: View {
    let name: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Sign In") {
    AuthenticationView()
        .environment(AuthenticationService())
}

#Preview("Firebase Status") {
    FirebaseStatusView()
}
