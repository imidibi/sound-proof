# Firebase Configuration and Data Fix Instructions

## Problem Summary

After renaming the app to "Approvl" and changing the bundle ID, there are multiple Firebase issues preventing the testreviewer@example.com user from accessing projects:

1. **Bundle ID Mismatch**: GoogleService-Info.plist is configured for old bundle ID
2. **Orphaned User Document**: Duplicate user document in Firestore from failed login attempt
3. **Incorrect Reviewer userId Values**: Reviewer documents reference the orphaned user ID instead of the real Firebase Auth user ID

## Current State

- **Firebase Auth User ID**: `PFpisuNuCtbq4L0uUVlDfKtKb813` ✅ (Correct)
- **Orphaned Firestore User ID**: `GOMK8z5lqdZqfZfqmb0Dcprf4K12` ❌ (Should be deleted)
- **Reviewer Documents**: Currently pointing to orphaned ID ❌ (Must be updated)

---

## Step 1: Update GoogleService-Info.plist

### Why This Is Needed
The app's bundle ID changed from `salesdiver.Session-Proof` to `com.studioguru.approvl`, but the Firebase configuration file still references the old bundle ID. This causes Firebase SDK warnings and potential connection issues.

### Instructions

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click the gear icon → **Project Settings**
4. Scroll to "Your apps" section
5. Find the iOS app with bundle ID `com.studioguru.approvl`
   - If it doesn't exist, you need to **add a new iOS app** with this bundle ID
   - If it exists, select it
6. Click **Download GoogleService-Info.plist**
7. In Xcode, locate the current `GoogleService-Info.plist` file
8. **Replace it** with the newly downloaded file
9. Clean and rebuild the project

---

## Step 2: Delete Orphaned User Document

### Why This Is Needed
When you couldn't log in due to the keychain issue, the app created a Firestore user document without a corresponding Firebase Auth user. This orphaned document is confusing the system.

### Instructions

1. In Firebase Console, go to **Firestore Database**
2. Navigate to the `users` collection
3. Find the document with ID: `GOMK8z5lqdZqfZfqmb0Dcprf4K12`
4. Verify it has email: `testreviewer@example.com`
5. **Delete this document** (trash icon)
6. Confirm deletion

**After deletion**, you should have only ONE user document with:
- ID: `PFpisuNuCtbq4L0uUVlDfKtKb813`
- Email: `testreviewer@example.com`

---

## Step 3: Fix Reviewer Documents - Update userId Fields

### Why This Is Needed
The reviewer documents in each project are storing the orphaned user ID in their `userId` field. Firebase security rules check this field to grant access. We need to update all reviewer documents to use the correct Firebase Auth user ID.

### Projects to Update
Based on the console logs, testreviewer@example.com is invited to these projects:
- `LKoTUb5miV70zb1Bho8O`
- `NjPYUk0bUpn1aYuO4rCx`
- `PuY3DYRrwCDXcvlXMKCp`

### Instructions for Each Project

For **each of the 3 projects** listed above:

1. In Firestore, navigate to: `projects/{projectId}/reviewers`
2. You should see **two** reviewer documents for testreviewer@example.com:
   - One with UUID-based ID (e.g., `8868227A-D66B-495E-BD5C-1AFD8FA58C6B`)
   - One with userId-based ID (`GOMK8z5lqdZqfZfqmb0Dcprf4K12`)

#### Update UUID-Based Reviewer Document

3. Open the UUID-based reviewer document
4. Find the `userId` field
5. Change it from: `GOMK8z5lqdZqfZfqmb0Dcprf4K12`
6. To: `PFpisuNuCtbq4L0uUVlDfKtKb813`
7. Click **Update**

#### Update userId-Based Reviewer Document

This document is used by Firebase security rules to grant access.

8. **Delete** the document with ID `GOMK8z5lqdZqfZfqmb0Dcprf4K12`
9. **Create a new document** in the same reviewers subcollection:
   - Document ID: `PFpisuNuCtbq4L0uUVlDfKtKb813` (use the correct user ID)
   - Copy all fields from the deleted document:
     - `email`: `testreviewer@example.com`
     - `userId`: `PFpisuNuCtbq4L0uUVlDfKtKb813`
     - `role`: (whatever role was set)
     - `invitedAt`: (copy timestamp)
     - `status`: `accepted`
     - Any other fields present

10. Repeat steps 3-9 for all 3 projects

---

## Step 4: Verify Security Rules Allow Access

### Check Current Rules

In Firebase Console → Firestore Database → Rules, verify the `isProjectReviewer()` function looks like this:

```javascript
function isProjectReviewer(projectId) {
  return exists(/databases/$(database)/documents/projects/$(projectId)/reviewers/$(request.auth.uid));
}
```

This function checks if a reviewer document exists where the document ID equals the Firebase Auth user ID (`request.auth.uid`).

After Step 3, these documents should now exist with the correct ID.

---

## Step 5: Test the Fix

1. In Xcode, clean build folder (⇧⌘K)
2. Build and run the app
3. Log in as testreviewer@example.com with password: `password123`
4. Check the console for:
   - ✅ No bundle ID mismatch warnings
   - ✅ "Found 6 reviewer records"
   - ✅ Projects fetched successfully (no permission errors)
   - ✅ Projects appear in the project list

---

## Expected Console Output After Fix

```
🔐 Login successful for user: PFpisuNuCtbq4L0uUVlDfKtKb813
✉️ Found reviewer in project LKoTUb5miV70zb1Bho8O: PFpisuNuCtbq4L0uUVlDfKtKb813
✅ Successfully fetched project: [Project Name]
📊 Synced X projects, Y songs, Z mixes
```

---

## Troubleshooting

### If projects still don't appear:

1. Check the `status` field in reviewer documents - should be `accepted` not `pending`
2. Verify the userId-based document ID exactly matches: `PFpisuNuCtbq4L0uUVlDfKtKb813`
3. Check Firebase Auth to confirm user is signed in with that ID
4. Review Firestore security rules - the `isProjectReviewer()` function must exist

### If bundle ID warning persists:

1. Ensure you downloaded the GoogleService-Info.plist for `com.studioguru.approvl` specifically
2. Check the plist file in a text editor - the `BUNDLE_ID` field should be `com.studioguru.approvl`
3. Clean Derived Data: Xcode → Preferences → Locations → Derived Data → Delete

---

## Summary Checklist

- [ ] Download and replace GoogleService-Info.plist for new bundle ID
- [ ] Delete orphaned user document `GOMK8z5lqdZqfZfqmb0Dcprf4K12` from users collection
- [ ] Update userId field in UUID-based reviewer documents (3 projects × 1 document = 3 updates)
- [ ] Delete and recreate userId-based reviewer documents with correct ID (3 projects)
- [ ] Clean build and test login
- [ ] Verify projects sync and appear in app

---

## Questions?

If you encounter any issues during these steps or need clarification, let me know which step you're on and what's happening.
