//
//  AuthenticationView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import SwiftUI

struct AuthenticationView: View {
    @State private var isSignUp = false
    
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
        }
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
        
        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
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
        
        do {
            try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName,
                role: selectedRole
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview("Sign In") {
    AuthenticationView()
        .environment(AuthenticationService())
}
