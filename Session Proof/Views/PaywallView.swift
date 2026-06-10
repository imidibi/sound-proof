//
//  PaywallView.swift
//  Session Proof
//
//  Created by Claude on 5/31/26.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AuthenticationService.self) private var authService
    
    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showError = false
    @State private var purchaseSuccess = false
    
    /// Is user currently in an active trial?
    private var isInActiveTrial: Bool {
        authService.currentUser?.isInTrial ?? false
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        if isInActiveTrial {
                            Text("Subscribe to Producer")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Keep access to all your projects and features")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Unlock Producer Features")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Start your 14-day free trial")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 32)
                    
                    // Features list
                    VStack(alignment: .leading, spacing: 16) {
                        if isInActiveTrial {
                            // Features for trial users (emphasize keeping access)
                            FeatureRow(icon: "folder.fill", title: "Retain Access to Projects", description: "Keep all your projects and work")
                            FeatureRow(icon: "waveform", title: "Continue Uploading Mixes", description: "Upload and share multiple mix versions")
                            FeatureRow(icon: "person.2", title: "Keep All Approvers", description: "Maintain your collaborator relationships")
                            FeatureRow(icon: "bubble.left.and.bubble.right", title: "Preserve All Feedback", description: "Keep all comments and approvals")
                            FeatureRow(icon: "icloud", title: "Cloud Sync", description: "Access your projects on all your devices")
                            FeatureRow(icon: "checkmark.seal", title: "Full Producer Features", description: "Unlimited projects and collaboration")
                        } else {
                            // Features for new users
                            FeatureRow(icon: "folder.badge.plus", title: "Unlimited Projects", description: "Create and manage unlimited music projects")
                            FeatureRow(icon: "waveform", title: "Upload Mixes", description: "Upload and share multiple mix versions")
                            FeatureRow(icon: "person.2", title: "Invite Approvers", description: "Collaborate with unlimited reviewers")
                            FeatureRow(icon: "bubble.left.and.bubble.right", title: "Comments & Feedback", description: "Get timestamped comments on your mixes")
                            FeatureRow(icon: "checkmark.seal", title: "Track Approvals", description: "Know exactly who approved what")
                            FeatureRow(icon: "icloud", title: "Cloud Sync", description: "Access your projects on all your devices")
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Subscription options
                    VStack(spacing: 12) {
                        ForEach(subscriptionService.availableProducts) { product in
                            SubscriptionOptionView(
                                product: product,
                                isSelected: selectedProductID == product.id,
                                onSelect: {
                                    selectedProductID = product.id
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Purchase button(s)
                    VStack(spacing: 12) {
                        // Main button
                        Button {
                            Task {
                                await purchaseSubscription()
                            }
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                }
                                Text(isPurchasing ? "Processing..." : (isInActiveTrial ? "Subscribe Now" : "Start Free Trial"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedProductID != nil && !isPurchasing ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(selectedProductID == nil || isPurchasing)
                        
                        // Subscribe Now option for new users (skip trial)
                        if !isInActiveTrial {
                            Button {
                                Task {
                                    await purchaseSubscription()
                                }
                            } label: {
                                Text("Subscribe Now")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            .disabled(selectedProductID == nil || isPurchasing)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Trial details
                    VStack(spacing: 8) {
                        if isInActiveTrial {
                            Text(selectedPriceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("14-day free trial, then \(selectedPriceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("Cancel anytime in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Restore purchases
                    Button {
                        Task {
                            await restorePurchases()
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                    .disabled(isPurchasing)
                    
                    // Terms
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://studioguru.net/terms")!)
                        Text("•")
                        Link("Privacy Policy", destination: URL(string: "https://studioguru.net/privacy")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Auto-select yearly subscription (best value) if nothing selected
                if selectedProductID == nil {
                    selectedProductID = subscriptionService.availableProducts
                        .first(where: { $0.period == "year" })?.id
                        ?? subscriptionService.availableProducts.first?.id
                }
            }
            .alert("Welcome to Producer!", isPresented: $purchaseSuccess) {
                Button("Get Started") {
                    dismiss()
                }
            } message: {
                if isInActiveTrial {
                    Text("Your subscription is now active. Enjoy full access to all Producer features!")
                } else {
                    Text("Your 14-day free trial has started. Enjoy full access to all Producer features!")
                }
            }
            .alert("Purchase Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(purchaseError ?? "An error occurred")
            }
        }
    }
    
    private var selectedPriceText: String {
        guard let productID = selectedProductID,
              let product = subscriptionService.availableProducts.first(where: { $0.id == productID }) else {
            return "$9.99/month"
        }
        return "\(product.displayPrice)/\(product.period)"
    }
    
    private func purchaseSubscription() async {
        guard let productID = selectedProductID,
              let subscriptionProduct = subscriptionService.availableProducts.first(where: { $0.id == productID }) else {
            return
        }
        
        isPurchasing = true
        purchaseError = nil
        
        do {
            let transaction = try await subscriptionService.purchase(subscriptionProduct.product)
            
            if transaction != nil {
                #if DEBUG
                print("💳 Purchase transaction completed")
                #endif
                
                // Purchase successful - update subscription status
                await subscriptionService.updateSubscriptionStatus()
                
                #if DEBUG
                print("📊 SubscriptionService status: \(subscriptionService.subscriptionStatus.rawValue)")
                print("📊 SubscriptionService tier: \(subscriptionService.subscriptionTier.rawValue)")
                print("📊 Can create projects: \(subscriptionService.canCreateProjects)")
                #endif
                
                // Sync to Firestore
                await syncSubscriptionToFirestore()
                
                #if DEBUG
                print("☁️ Synced to Firestore")
                print("👤 Current user status: \(authService.currentUser?.subscriptionStatus ?? "nil")")
                print("👤 Current user tier: \(authService.currentUser?.subscriptionTier ?? "nil")")
                print("👤 Can create projects: \(authService.currentUser?.canCreateProjects ?? false)")
                #endif
                
                // Show success message
                await MainActor.run {
                    isPurchasing = false
                    purchaseSuccess = true
                }
                
                #if DEBUG
                print("✅ Purchase flow complete, showing success alert")
                #endif
            }
        } catch {
            await MainActor.run {
                isPurchasing = false
                purchaseError = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        
        do {
            try await subscriptionService.restorePurchases()
            
            // Sync to Firestore
            await syncSubscriptionToFirestore()
            
            await MainActor.run {
                if subscriptionService.canCreateProjects {
                    dismiss()
                } else {
                    purchaseError = "No active subscriptions found"
                    showError = true
                }
            }
        } catch {
            await MainActor.run {
                purchaseError = error.localizedDescription
                showError = true
            }
        }
        
        await MainActor.run {
            isPurchasing = false
        }
    }
    
    private func syncSubscriptionToFirestore() async {
        do {
            try await authService.updateSubscriptionStatus(
                tier: subscriptionService.subscriptionTier.rawValue,
                status: subscriptionService.subscriptionStatus.rawValue,
                originalTransactionId: subscriptionService.originalTransactionId,
                trialStartedAt: subscriptionService.isInTrial ? subscriptionService.trialEndDate?.addingTimeInterval(-14 * 24 * 60 * 60) : nil,
                trialEndsAt: subscriptionService.trialEndDate,
                subscriptionExpiresAt: subscriptionService.subscriptionExpiryDate,
                gracePeriodEndsAt: subscriptionService.gracePeriodEndDate
            )
            print("✅ Synced subscription to Firestore (Transaction ID: \(subscriptionService.originalTransactionId ?? "none"))")
        } catch {
            print("❌ Failed to sync subscription to Firestore: \(error.localizedDescription)")
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct SubscriptionOptionView: View {
    let product: SubscriptionProduct
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if product.period == "year" {
                            Text("SAVE 17%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    if product.period == "year" {
                        Text("Only \(formatMonthlyPrice(product.pricePerMonth))/month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatMonthlyPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionService())
        .environment(AuthenticationService())
}
