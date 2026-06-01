# Notification Testing Guide

## Important: Proper Test Setup

### Why Notifications May Not Work
1. **Xcode Debugging/Paused State** - When the app is running from Xcode with debugger attached, notifications may not work properly
2. **Simulator** - Push notifications don't work on simulator, only real devices
3. **Stale Tokens** - FCM tokens can become invalid but aren't immediately cleaned up

## Proper Testing Procedure

### Step 1: Build and Install the App (Without Debugging)
1. In Xcode, select your iPad device
2. Build the app (Cmd+B)
3. **Archive the app** OR run it once, then **disconnect from debugger**:
   - Product → Stop (Cmd+.)
   - Close the app on iPad
   - Launch the app manually from home screen

### Step 2: Verify Notification Setup on iPad
1. Open the app (NOT from Xcode - launch manually)
2. Go to Settings → Support → **Notification Debug**
3. Tap **"Refresh FCM Token"**
4. Verify:
   - Authorization Status shows "Authorized" (green)
   - Current FCM Token is displayed
   - Saved Tokens in Firestore shows at least 1 token

5. Also check iOS Settings:
   - iOS Settings → Notifications → Approvl
   - Ensure "Allow Notifications" is ON
   - Enable Sounds, Badges, and Banners

### Step 3: Test Different Notification Types

#### Test A: Reviewer Invitation (What You Tried)
On Mac:
1. Remove testartist3 from a project (if already added)
2. Add testartist3 back to the project
3. On iPad - notification should appear within seconds

#### Test B: Comment Notification (Alternative Test)
On Mac:
1. Go to any mix in a project where testartist3 is an approver
2. Add a comment (text or voice)
3. On iPad - notification should appear within seconds

#### Test C: Approval Notification (If testartist3 is producer)
On iPad (if testartist3 owns a project):
1. Go to a mix and change approval status to "Approved"
2. On Mac - notification should appear

### Step 4: Check Firebase Functions Logs
On Mac terminal:
```bash
cd "/Users/ianmiller/Development/Session Proof/firebase-functions"
firebase functions:log
```

Look for:
- `📱 User [userId]: checking for FCM tokens`
- `✅ Found X tokens in fcmTokens array`
- `📤 Attempting to send...`
- `✅ Sent X notifications, ❌ 0 failed`

### Step 5: If Still Not Working

#### Check for Token Issues:
1. On iPad, in Notification Debug, tap "Refresh FCM Token" again
2. Note the token (first 20 chars)
3. Tap "Refresh" in the Saved Tokens section
4. Verify the current token appears in the saved list

#### Check Console Logs:
On Mac:
1. Connect iPad via cable
2. Open Console.app
3. Select your iPad from devices
4. Filter for "FCM" or "APNS" or "notification"
5. Watch the logs while testing

#### Common Issues:
- **"Token mismatch"** - The saved tokens in Firestore are old. Fix: Refresh token on iPad
- **"No notifications appear but logs say success"** - iOS is silently rejecting. Fix: Delete app, reinstall, re-authorize notifications
- **"Function not triggered"** - Firestore trigger isn't working. Check Firebase console

## Quick Checklist
- [ ] App installed and launched WITHOUT Xcode debugger
- [ ] Notification permissions authorized in app
- [ ] Notification permissions enabled in iOS Settings
- [ ] FCM token refreshed and saved to Firestore
- [ ] Cloud Functions deployed (firebase deploy --only functions)
- [ ] Testing on real device (not simulator)
- [ ] iPad is NOT in Do Not Disturb mode
- [ ] iPad has internet connection
