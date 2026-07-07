# App Store Trial Issue - Diagnosis & Fix

## Issue Report
Apple rejected the app stating: "The 14-day free trial did not work in their testing"

## Root Cause Analysis

### 1. **StoreKit Configuration Mismatch**
The local `Configuration.storekit` file had the trial period set to `P2W` (2 weeks) instead of the more explicit `P14D` (14 days). While technically equivalent, the explicit day format is clearer and matches what's typically used in App Store Connect.

**Fixed:** Changed both subscription products from `P2W` to `P14D`

### 2. **Critical: App Store Connect Configuration**
The local StoreKit configuration file is ONLY used for local testing in Xcode. Apple reviewers test using the **Sandbox environment** which pulls configuration from **App Store Connect**, not the local file.

## Required Actions in App Store Connect

### Step 1: Verify Subscription Configuration
1. Log into App Store Connect
2. Go to "My Apps" → "Approvl" → "Subscriptions"
3. Select the "Producer" subscription group
4. For BOTH products (`approvl.producer.monthly` and `approvl.producer.yearly`):

### Step 2: Check Introductory Offer Settings
For each subscription product, verify:

- **Introductory Offer Type**: "Free Trial"
- **Duration**: "14 Days" (NOT "2 Weeks")
- **Number of Periods**: 1
- **Available in All Territories**: ✓ Enabled
- **Status**: "Ready to Submit" or "Approved"

### Step 3: Verify Subscription Group Settings
- Ensure both products are in the same subscription group
- Verify the subscription group is set to "Auto-Renewable Subscriptions"

### Step 4: Check App Store Review Information
In the version information for App Store Review:
- Ensure the test account has NOT previously used the free trial
- Create a NEW Sandbox test account specifically for the review
- Provide this fresh test account to Apple in the "App Review Information" notes

## Code Changes Made

### Configuration.storekit
Changed trial period format from ISO 8601 weeks to explicit days:

```json
// Before:
"subscriptionPeriod" : "P2W"

// After:
"subscriptionPeriod" : "P14D"
```

This change ensures consistency with how App Store Connect expects the duration.

## Testing the Fix

### Local Testing (Xcode)
1. Build and run the app in Simulator or on a test device
2. Sign up as a new producer user
3. When the paywall appears, verify:
   - "Start your 14-day free trial" text is visible
   - Subscription options show the free trial offer
   - After purchase, the trial status is correctly detected

### Sandbox Testing (Critical for App Review)
1. Create a NEW Sandbox test account in App Store Connect:
   - Go to Users and Access → Sandbox → Testers
   - Click "+" to add a new tester
   - Use a unique email that has NEVER been used before

2. Sign out of all App Store accounts on test device

3. Install the app via TestFlight or development build

4. When prompted during first purchase:
   - Sign in with the NEW Sandbox account
   - Verify the free trial offer appears
   - Complete the purchase
   - Confirm trial starts successfully

5. Verify the trial in Settings → Manage Subscriptions

## Common Issues & Solutions

### Issue 1: "Free trial not available"
**Cause**: The sandbox test account has already used the free trial
**Solution**: Create a brand new sandbox test account

### Issue 2: Trial doesn't appear in subscription dialog
**Cause**: Introductory offer not configured in App Store Connect
**Solution**: Follow Step 2 above to configure the offer

### Issue 3: Trial shows but purchase fails
**Cause**: Subscription not approved or missing metadata
**Solution**: Ensure subscription is in "Ready to Submit" state with all required metadata

### Issue 4: Trial detection not working in app
**Cause**: Transaction doesn't have `offer?.type == .introductory`
**Solution**: This is fixed by proper App Store Connect configuration

## Implementation Details

### How Trial Detection Works

The app detects trials using StoreKit 2's transaction properties:

```swift
// In SubscriptionService.swift line 243
let isInTrial = transaction.offer?.type == .introductory

if isInTrial {
    subscriptionStatus = .trial
    trialEndDate = transaction.expirationDate
}
```

This ONLY works if:
1. The user has never used a trial before (per Apple's rules)
2. The introductory offer is properly configured in App Store Connect
3. The transaction contains offer information

### Trial Duration Calculation

The trial end date comes directly from the transaction:
```swift
trialEndDate = transaction.expirationDate
```

The start date is calculated when syncing to Firestore:
```swift
// PaywallView.swift line 310
trialStartedAt: subscriptionService.isInTrial ?
    subscriptionService.trialEndDate?.addingTimeInterval(-14 * 24 * 60 * 60) : nil
```

## For App Review Submission

Include this in the "App Review Information" notes:

```
SUBSCRIPTION TESTING INSTRUCTIONS:

1. Use the provided Sandbox test account (fresh account, never used trial)
2. Sign up as a new "Producer" user in the app
3. The paywall will appear automatically
4. Select either Monthly or Yearly subscription
5. Tap "Start Free Trial" button
6. Complete the Sandbox purchase flow
7. Verify "14-day free trial has started" confirmation appears
8. Verify you can create projects and access all Producer features

Note: The free trial ONLY works with a Sandbox account that has never
previously used a trial for this subscription. If the trial doesn't appear,
please use a fresh Sandbox account.

Test Account Provided:
- Email: [NEW_SANDBOX_EMAIL]
- Password: [SANDBOX_PASSWORD]
```

## Checklist for Resubmission

- [ ] Updated `Configuration.storekit` with `P14D` format
- [ ] Verified introductory offer in App Store Connect (14 days, free)
- [ ] Created NEW Sandbox test account (never used before)
- [ ] Tested trial purchase with new Sandbox account
- [ ] Verified trial status appears correctly in app
- [ ] Confirmed "Start Free Trial" button works
- [ ] Tested that trial gives full Producer access
- [ ] Updated App Review notes with testing instructions
- [ ] Provided fresh Sandbox test credentials

## Additional Notes

### Why P14D vs P2W?

While ISO 8601 considers `P2W` and `P14D` equivalent:
- `P2W` = 2 weeks = 14 days
- `P14D` = 14 days explicitly

Apple's systems and App Store Connect use the explicit day format for trial periods. Using `P14D` ensures:
1. Clarity for reviewers
2. Consistency with App Store Connect configuration
3. No ambiguity in interpretation

### Trial Eligibility Rules

Per Apple's subscription guidelines:
- Free trials are offered ONCE per Apple ID
- If a user has ever used a trial for ANY product in the subscription group, they cannot use it again
- This applies even if they cancelled and created a new account
- Sandbox accounts follow the same rules (can only use trial once)

### Trial Best Practices

1. **Always test with fresh Sandbox accounts**
2. **Keep sandbox credentials organized** - mark which ones have used trials
3. **Test the full purchase flow** - don't just verify the offer appears
4. **Verify trial status in-app** - ensure your app correctly detects the trial
5. **Test trial expiration** - verify what happens when trial ends (StoreKit testing only)

## Support & Debugging

### Debug Logging

The app includes comprehensive logging for subscription status:

```
📊 Subscription status: Trial (ends [date])
   Original Transaction ID: [transaction_id]
```

### Common Log Messages

**Success:**
```
✅ Loaded 2 subscription products
🛒 Attempting to purchase: Producer Monthly
✅ Purchase successful: Producer Monthly
📊 Subscription status: Trial (ends ...)
```

**Problems:**
```
❌ Failed to load products: [error]
⚠️ Could not verify transaction
ℹ️ User cancelled purchase
```

### Testing in Production

**WARNING**: Do NOT test subscriptions in production with real accounts. Always use:
- Development builds with Xcode
- TestFlight builds with Sandbox accounts
- StoreKit Testing in Xcode

## References

- [Apple: Implementing Introductory Offers](https://developer.apple.com/documentation/storekit/in-app_purchase/implementing_introductory_offers_in_your_app)
- [Apple: Testing In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases)
- [ISO 8601 Duration Format](https://en.wikipedia.org/wiki/ISO_8601#Durations)

## Next Steps

1. Commit these changes
2. Build and archive new version
3. Upload to App Store Connect
4. Create fresh Sandbox test account
5. Test thoroughly with new Sandbox account
6. Update App Review notes with testing instructions
7. Submit for review

---

**Updated**: January 2026
**Status**: Ready for testing and resubmission
