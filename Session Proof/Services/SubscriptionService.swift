//
//  SubscriptionService.swift
//  Session Proof
//
//  Created by Claude on 5/31/26.
//

import Foundation
import StoreKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Subscription tier for users
enum SubscriptionTier: String, Codable {
    case free
    case producer
}

/// Subscription status
enum SubscriptionStatus: String, Codable {
    case active      // Paid and active
    case trial       // In free trial period
    case expired     // Subscription expired, in grace period
    case cancelled   // Subscription cancelled, no access
    case free        // Free tier (never subscribed)
}

/// Store product information
struct SubscriptionProduct: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
    let period: String
    let product: Product
    
    var pricePerMonth: Decimal {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.price
        }
        
        switch period.unit {
        case .month:
            return product.price / Decimal(period.value)
        case .year:
            return product.price / Decimal(period.value * 12)
        default:
            return product.price
        }
    }
}

/// Service for managing App Store subscriptions using StoreKit 2
@Observable
final class SubscriptionService {
    // Product IDs
    static let monthlyProductID = "approvl.producer.monthly"
    static let yearlyProductID = "approvl.producer.yearly"
    
    // Published state
    var availableProducts: [SubscriptionProduct] = []
    var purchasedProductIDs: Set<String> = []
    var subscriptionStatus: SubscriptionStatus = .free
    var subscriptionTier: SubscriptionTier = .free
    var currentSubscription: Product.SubscriptionInfo.Status?
    
    // Trial and expiry tracking
    var trialEndDate: Date?
    var subscriptionExpiryDate: Date?
    var gracePeriodEndDate: Date?
    var originalTransactionId: String?  // StoreKit original transaction ID
    
    // Environment detection
    var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
    
    private var updateTask: Task<Void, Never>?
    private var transactionListener: Task<Void, Never>?
    
    init() {
        // Start listening for transaction updates
        transactionListener = listenForTransactions()
        
        // Load products and subscription status
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateTask?.cancel()
        transactionListener?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load available subscription products from the App Store
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [
                Self.monthlyProductID,
                Self.yearlyProductID
            ])
            
            await MainActor.run {
                self.availableProducts = products.map { product in
                    let period = product.subscription?.subscriptionPeriod.unit == .year ? "year" : "month"
                    return SubscriptionProduct(
                        id: product.id,
                        displayName: product.displayName,
                        description: product.description,
                        displayPrice: product.displayPrice,
                        period: period,
                        product: product
                    )
                }.sorted { $0.pricePerMonth < $1.pricePerMonth }
                
                print("✅ Loaded \(products.count) subscription products")
            }
        } catch {
            print("❌ Failed to load products: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Purchase Flow
    
    /// Purchase a subscription product
    func purchase(_ product: Product) async throws -> Transaction? {
        print("🛒 Attempting to purchase: \(product.displayName)")
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            // Update subscription status
            await updateSubscriptionStatus()
            
            // Finish the transaction
            await transaction.finish()
            
            print("✅ Purchase successful: \(product.displayName)")
            return transaction
            
        case .userCancelled:
            print("ℹ️ User cancelled purchase")
            return nil
            
        case .pending:
            print("⏳ Purchase pending (Ask to Buy or payment issue)")
            return nil
            
        @unknown default:
            print("⚠️ Unknown purchase result")
            return nil
        }
    }
    
    /// Restore previous purchases
    func restorePurchases() async throws {
        print("🔄 Restoring purchases...")
        
        try await AppStore.sync()
        await updateSubscriptionStatus()
        
        print("✅ Purchases restored")
    }
    
    // MARK: - Subscription Status
    
    /// Update current subscription status
    func updateSubscriptionStatus() async {
        var highestStatus: Product.SubscriptionInfo.Status?
        
        // Check all subscription statuses
        for product in availableProducts.map(\.product) {
            guard let subscription = product.subscription else { continue }
            
            let statuses = try? await subscription.status
            
            for status in statuses ?? [] {
                // Get the verified transaction
                guard let transaction = try? checkVerified(status.transaction) else {
                    continue
                }
                
                // Track highest priority status
                if highestStatus == nil || status.state.priority > highestStatus!.state.priority {
                    highestStatus = status
                }
                
                // Track purchased products
                if status.state == .subscribed || status.state == .inGracePeriod {
                    _ = await MainActor.run {
                        purchasedProductIDs.insert(transaction.productID)
                    }
                }
            }
        }
        
        await MainActor.run {
            self.currentSubscription = highestStatus
            updateLocalStatus(from: highestStatus)
        }
    }
    
    /// Update local status properties from subscription info
    private func updateLocalStatus(from status: Product.SubscriptionInfo.Status?) {
        guard let status = status else {
            // No subscription
            subscriptionStatus = .free
            subscriptionTier = .free
            trialEndDate = nil
            subscriptionExpiryDate = nil
            gracePeriodEndDate = nil
            print("📊 Subscription status: Free (no subscription)")
            return
        }
        
        let state = status.state
        
        // Get the verified transaction
        guard let transaction = try? checkVerified(status.transaction) else {
            print("⚠️ Could not verify transaction")
            return
        }

        // Store the original transaction ID (unique per purchase, persists across renewals)
        originalTransactionId = String(transaction.originalID)

        // Determine subscription status based on renewal state
        // Check if user is in trial by checking the offer property
        let isInTrial = transaction.offer?.type == .introductory
        
        if isInTrial {
            // User is in trial period
            subscriptionStatus = .trial
            subscriptionTier = .producer
            trialEndDate = transaction.expirationDate
            print("📊 Subscription status: Trial (ends \(trialEndDate?.formatted() ?? "unknown"))")
            print("   Original Transaction ID: \(originalTransactionId ?? "none")")
        } else if state == .subscribed {
            // Active paid subscription
            subscriptionStatus = .active
            subscriptionTier = .producer
            subscriptionExpiryDate = transaction.expirationDate
            print("📊 Subscription status: Active (renews \(subscriptionExpiryDate?.formatted() ?? "unknown"))")
        } else if state == .inGracePeriod || state == .inBillingRetryPeriod {
            // Grace period after expiry
            subscriptionStatus = .expired
            subscriptionTier = .producer // Still have access during grace period
            subscriptionExpiryDate = transaction.expirationDate
            // Grace period is 30 days after expiry
            if let expiryDate = transaction.expirationDate {
                gracePeriodEndDate = Calendar.current.date(byAdding: .day, value: 30, to: expiryDate)
            }
            print("📊 Subscription status: Grace Period (ends \(gracePeriodEndDate?.formatted() ?? "unknown"))")
        } else {
            // Expired or revoked
            subscriptionStatus = .cancelled
            subscriptionTier = .free
            subscriptionExpiryDate = transaction.expirationDate
            print("📊 Subscription status: Expired/Cancelled")
        }
    }
    
    // MARK: - Entitlements
    
    /// Check if user can create projects (has active subscription or trial)
    var canCreateProjects: Bool {
        subscriptionStatus == .active || subscriptionStatus == .trial
    }
    
    /// Check if user has an active subscription (not trial)
    var hasActiveSubscription: Bool {
        subscriptionStatus == .active
    }
    
    /// Check if user is in trial
    var isInTrial: Bool {
        subscriptionStatus == .trial
    }
    
    /// Check if user is in grace period
    var isInGracePeriod: Bool {
        subscriptionStatus == .expired
    }
    
    /// Days remaining in trial
    var trialDaysRemaining: Int? {
        guard let trialEndDate = trialEndDate else { return nil }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate)
        return components.day
    }
    
    /// Days remaining in grace period
    var gracePeriodDaysRemaining: Int? {
        guard let gracePeriodEndDate = gracePeriodEndDate else { return nil }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEndDate)
        return components.day
    }
    
    // MARK: - Transaction Listening
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached { [weak self] in
            guard let self = self else { return }
            
            for await result in Transaction.updates {
                guard let transaction = try? await self.checkVerified(result) else {
                    continue
                }
                
                // Update subscription status when transaction changes
                await self.updateSubscriptionStatus()
                
                // Finish the transaction
                await transaction.finish()
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify a transaction is legitimate
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Manage Subscription
    
    /// Open the App Store manage subscriptions page
    @MainActor
    func openManageSubscriptions() {
        #if os(iOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Subscription State Priority

extension Product.SubscriptionInfo.RenewalState {
    var priority: Int {
        if self == .subscribed {
            return 4
        } else if self == .inGracePeriod {
            return 3
        } else if self == .inBillingRetryPeriod {
            return 2
        } else if self == .expired {
            return 1
        } else if self == .revoked {
            return 0
        } else {
            return -1
        }
    }
}
