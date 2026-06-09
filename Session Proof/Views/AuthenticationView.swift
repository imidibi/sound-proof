//
//  AuthenticationView.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import SwiftUI
import AuthenticationServices

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
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingAppleSignIn = false

    let showSignUp: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App branding
            VStack(spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                Text("Approvl")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Text("Professional Mix Approval")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            VStack(spacing: 20) {
                // Sign in with Apple (for Producers)
                VStack(spacing: 12) {
                    Button {
                        showingAppleSignIn = true
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Sign in with Apple")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("Recommended for Producers")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                }

                // Email/Password (for Approvers)
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        signIn()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign In")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Text("For invited Approvers")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 40)

            // Sign up link
            Button {
                showSignUp()
            } label: {
                Text("Don't have an account? Sign Up")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }
            .padding(.top, 8)

            Spacer()
                .frame(height: 60)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingAppleSignIn) {
            AppleSignInSheet()
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

struct SignUpView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var selectedRole: UserRole = .producer
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingAppleSignIn = false
    @State private var hasInvitation = false
    @State private var isCheckingInvitation = false

    let showSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                    Text("Create Account")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)

                // Sign up with Apple (for Producers)
                VStack(spacing: 12) {
                    Button {
                        showingAppleSignIn = true
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Sign up with Apple")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("Best for Producers (subscription required)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 40)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 40)

                // Email/Password signup
                VStack(spacing: 20) {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Show invitation message if found
                    if hasInvitation {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(.green)
                            Text("Invitation found! You'll be added as an Approver.")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .padding()
                        .background(Color.green.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // Role selection (only if no invitation)
                        Picker("Account Type", selection: $selectedRole) {
                            Text("Producer").tag(UserRole.producer)
                            Text("Approver").tag(UserRole.artist)
                        }
                        .pickerStyle(.segmented)
                        .disabled(hasInvitation)

                        Text(selectedRole == .producer
                             ? "Create unlimited projects and manage mix approvals"
                             : "Review and approve mixes shared with you")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        signUp()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Account")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isLoading || !isFormValid)
                }
                .padding(.horizontal, 40)

                // Sign in link
                Button {
                    showSignIn()
                } label: {
                    Text("Already have an account? Sign In")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }

                Spacer()
            }
        }
        .alert("Sign Up Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingAppleSignIn) {
            AppleSignInSheet()
        }
        .onChange(of: email) { oldValue, newValue in
            // Check for invitation when email changes
            guard !newValue.isEmpty, newValue.contains("@") else {
                hasInvitation = false
                return
            }

            Task {
                isCheckingInvitation = true
                if let suggestedRole = await authService.getSuggestedRoleForEmail(newValue) {
                    await MainActor.run {
                        hasInvitation = true
                        selectedRole = suggestedRole
                    }
                } else {
                    await MainActor.run {
                        hasInvitation = false
                    }
                }
                isCheckingInvitation = false
            }
        }
    }

    private var isFormValid: Bool {
        !displayName.isEmpty &&
        !email.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6
    }

    private func signUp() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Check for pending invitations before signup
                let suggestedRole = await authService.getSuggestedRoleForEmail(email)
                let finalRole = suggestedRole ?? selectedRole

                // If invitation found, override selected role with Approver
                if suggestedRole != nil {
                    print("✉️ Found invitation for \(email), auto-assigning as Approver")
                }

                try await authService.signUp(email: email, password: password, displayName: displayName, role: finalRole)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

// Separate sheet for Apple Sign In
struct AppleSignInSheet: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var showRoleSelection = false
    @State private var selectedRole: UserRole = .producer
    @State private var pendingAuthorization: ASAuthorization?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var userEmail: String?
    @State private var userName: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary)

                    Text("Sign in with Apple")
                        .font(.title2.bold())

                    Text("Secure authentication using your Apple ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                SignInWithAppleButton(
                    onRequest: { request in
                        let preparedRequest = authService.prepareSignInWithAppleRequest()
                        request.requestedScopes = preparedRequest.requestedScopes
                        request.nonce = preparedRequest.nonce
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            pendingAuthorization = authorization

                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                userEmail = appleIDCredential.email

                                if let fullName = appleIDCredential.fullName {
                                    let nameComponents = [fullName.givenName, fullName.familyName]
                                        .compactMap { $0 }
                                    userName = nameComponents.joined(separator: " ")
                                }

                                // Check for pending invitations
                                if let email = appleIDCredential.email {
                                    Task {
                                        if let suggestedRole = await authService.getSuggestedRoleForEmail(email) {
                                            await MainActor.run {
                                                selectedRole = suggestedRole
                                            }
                                            handleRoleSelection()
                                        } else {
                                            await MainActor.run {
                                                showRoleSelection = true
                                            }
                                        }
                                    }
                                } else {
                                    showRoleSelection = true
                                }
                            }

                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)

                if isProcessing {
                    ProgressView()
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showRoleSelection) {
                RoleSelectionSheet(
                    selectedRole: $selectedRole,
                    userEmail: userEmail,
                    userName: userName,
                    onContinue: {
                        handleRoleSelection()
                    },
                    onUseOtherAccount: {
                        showRoleSelection = false
                        pendingAuthorization = nil
                        userEmail = nil
                        userName = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .alert("Sign In Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(errorMessage ?? "An error occurred during sign in")
            }
        }
    }

    private func handleRoleSelection() {
        guard let authorization = pendingAuthorization else { return }

        isProcessing = true

        Task {
            do {
                try await authService.handleSignInWithApple(authorization: authorization, role: selectedRole)

                await MainActor.run {
                    isProcessing = false
                    showRoleSelection = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct RoleSelectionSheet: View {
    @Binding var selectedRole: UserRole
    let userEmail: String?
    let userName: String?
    let onContinue: () -> Void
    let onUseOtherAccount: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose Your Role")
                    .font(.title2.bold())
                    .padding(.top)

                // Show signed-in account info
                if let email = userEmail ?? userName {
                    VStack(spacing: 4) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text("Select how you'll use Approvl")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    RoleOptionButton(
                        role: .producer,
                        title: "Producer",
                        description: "Create unlimited projects and manage mix approvals",
                        icon: "music.note.list",
                        isSelected: selectedRole == .producer
                    ) {
                        selectedRole = .producer
                    }

                    RoleOptionButton(
                        role: .artist,
                        title: "Approver",
                        description: "Review and approve mixes shared with you",
                        icon: "checkmark.circle",
                        isSelected: selectedRole == .artist
                    ) {
                        selectedRole = .artist
                    }
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onUseOtherAccount()
                        dismiss()
                    } label: {
                        Text("Use a different Apple account")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RoleOptionButton: View {
    let role: UserRole
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AuthenticationView()
        .environment(AuthenticationService())
}
