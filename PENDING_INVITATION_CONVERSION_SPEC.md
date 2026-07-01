# Pending Invitation to User Conversion Specification

## Overview
This document specifies the process for converting a pending invitation in Firestore to a real user account when an invited approver creates their account, either through the iOS/Mac app or the web app (approvl.web.app).

## Data Structure

### Firestore Collections Involved

1. **`pending_invitations` collection** (root level)
   - Document ID: `{email}` (lowercase, normalized)
   - Fields:
     - `inviteeEmail`: String (lowercase email)
     - `projectId`: String (Firestore project ID)
     - `reviewerId`: String (UUID of the reviewer document)
     - `displayName`: String (invited person's name)
     - `createdAt`: Timestamp

2. **`projects/{projectId}/reviewers/{reviewerId}` collection**
   - Document ID: `{reviewerId}` (UUID-based)
   - Fields:
     - `displayName`: String
     - `email`: String (lowercase)
     - `userId`: String | null (Firebase Auth UID - **null for pending invitations**)
     - `role`: String (e.g., "Reviewer", "Owner", "Viewer")
     - `inviteStatus`: String (e.g., "Sent", "Accepted", "Declined")
     - `isKeyApprover`: Boolean
     - `createdAt`: Timestamp
     - `acceptedAt`: Timestamp | null
     - `invitedAt`: Timestamp | null
     - `invitationToken`: String | null

3. **`projects/{projectId}/reviewers/{userId}` collection** (for security rules)
   - Document ID: `{userId}` (Firebase Auth UID)
   - Same fields as UUID-based document, plus:
     - `primaryReviewerId`: String (reference to UUID-based document)

4. **`users` collection**
   - Document ID: `{userId}` (Firebase Auth UID)
   - Fields:
     - `email`: String
     - `displayName`: String
     - `role`: String ("producer", "artist", "studio")
     - `createdAt`: Timestamp
     - Plus other user profile fields

## Conversion Process

### When a User Creates an Account

When an invited approver creates an account (via signup on web or mobile app), the following steps occur:

#### 1. **Account Creation**
```
POST to Firebase Auth
- Email: {invitee_email}
- Password: {chosen_password}
- Display Name: {display_name}
```

This creates:
- Firebase Auth user with UID
- `users/{userId}` document in Firestore with:
  - `email`: normalized (lowercase)
  - `displayName`: provided name
  - `role`: "artist" (if invited) or "producer" (if self-signup)
  - `createdAt`: current timestamp
  - `subscriptionStatus`: "free"
  - `subscriptionTier`: "free"

#### 2. **Check for Pending Invitations** (iOS/Mac App Process)

The app automatically runs this on first login after account creation:

```swift
// Called from ContentView.swift on initial sync
try await syncService.acceptPendingInvitations(
    userId: userId,
    userEmail: userEmail,
    modelContext: modelContext
)
```

#### 3. **Find Pending Invitations**

Query the `pending_invitations` collection:
```
GET /pending_invitations/{normalized_email}
```

This returns:
- `projectId`: The project(s) the user was invited to
- `reviewerId`: The UUID of the reviewer document to update

#### 4. **Update Reviewer Documents**

For each pending invitation found:

**a. Update UUID-based reviewer document:**
```
PATCH /projects/{projectId}/reviewers/{reviewerId}
{
  "userId": "{firebase_auth_uid}",
  "inviteStatus": "Accepted",
  "acceptedAt": Timestamp(Date())
}
```

**b. Create userId-based reviewer document (for security rules):**
```
SET /projects/{projectId}/reviewers/{userId}
{
  "email": "{email}",
  "userId": "{firebase_auth_uid}",
  "inviteStatus": "Accepted",
  "acceptedAt": Timestamp(Date()),
  "displayName": "{display_name}",
  "role": "{role}",
  "isKeyApprover": {boolean},
  "createdAt": {original_timestamp},
  "primaryReviewerId": "{reviewerId}"
}
```

#### 5. **Clean Up Pending Invitation**

Delete the pending invitation document:
```
DELETE /pending_invitations/{normalized_email}
```

## Web App Implementation Requirements

To implement this in your web app (approvl.web.app), you need to:

### 1. **On Signup**

After creating the Firebase Auth account and user profile:

```javascript
async function acceptPendingInvitations(userId, userEmail) {
  const normalizedEmail = userEmail.toLowerCase().trim();

  // Step 1: Check for pending invitation
  const pendingInviteRef = db.collection('pending_invitations')
    .doc(normalizedEmail);
  const pendingInviteDoc = await pendingInviteRef.get();

  if (!pendingInviteDoc.exists) {
    console.log('No pending invitations found');
    return;
  }

  const invitationData = pendingInviteDoc.data();
  const { projectId, reviewerId } = invitationData;

  // Step 2: Update UUID-based reviewer document
  const reviewerRef = db.collection('projects')
    .doc(projectId)
    .collection('reviewers')
    .doc(reviewerId);

  await reviewerRef.update({
    userId: userId,
    inviteStatus: 'Accepted',
    acceptedAt: firebase.firestore.FieldValue.serverTimestamp()
  });

  // Step 3: Get full reviewer data for userId-based document
  const reviewerDoc = await reviewerRef.get();
  const reviewerData = reviewerDoc.data();

  // Step 4: Create userId-based reviewer document (for security rules)
  const userIdReviewerRef = db.collection('projects')
    .doc(projectId)
    .collection('reviewers')
    .doc(userId);

  await userIdReviewerRef.set({
    ...reviewerData,
    userId: userId,
    inviteStatus: 'Accepted',
    acceptedAt: firebase.firestore.FieldValue.serverTimestamp(),
    primaryReviewerId: reviewerId
  });

  // Step 5: Delete pending invitation
  await pendingInviteRef.delete();

  console.log('✅ Successfully accepted pending invitation for project:', projectId);
}
```

### 2. **On Login**

After successful login, also check for and accept any pending invitations:

```javascript
async function onLoginSuccess(user) {
  // Accept any pending invitations
  await acceptPendingInvitations(user.uid, user.email);

  // Then load user's projects
  await loadUserProjects(user.uid);
}
```

## Security Rules Considerations

The Firestore security rules should allow:

1. **Unauthenticated reads** of `pending_invitations/{email}` for the signup flow
2. **Authenticated writes** to reviewer documents when `userId` matches `request.auth.uid`
3. **Project access** based on existence of `/projects/{projectId}/reviewers/{request.auth.uid}`

## Error Handling

### Common Issues

1. **Invitation not found**: User wasn't invited but signing up anyway
   - Action: Allow normal signup, they won't have project access

2. **Invitation already accepted**: User created account on different device
   - Action: Skip update, just load existing project access

3. **Multiple invitations**: User invited to multiple projects
   - Action: Process all pending invitations in a loop

4. **Network timeout**: Firestore operation fails
   - Action: Retry on next login/app launch

## Testing Checklist

- [ ] Create pending invitation via iOS/Mac app
- [ ] Sign up on web app with invited email
- [ ] Verify `userId` field is populated in UUID-based reviewer document
- [ ] Verify userId-based reviewer document is created
- [ ] Verify pending invitation is deleted
- [ ] Verify user can access project on web app
- [ ] Verify user can access project on iOS/Mac app after sync
- [ ] Test with multiple pending invitations
- [ ] Test signup with non-invited email (should work normally)

## Key Differences Between Platforms

### iOS/Mac App
- Automatically runs `acceptPendingInvitations()` on first login
- Uses Swift/SwiftUI with FirebaseFirestore SDK
- Timeout protection (10 seconds)
- Integrated with local SwiftData sync

### Web App
- Must manually implement the same logic
- Uses JavaScript with Firebase Web SDK
- Should handle promises/async properly
- No local database sync needed

## Implementation Priority

1. **Critical**: Update UUID-based reviewer document with `userId`
2. **Critical**: Create userId-based reviewer document for security rules
3. **Important**: Delete pending invitation to avoid duplicates
4. **Optional**: Send confirmation email/notification

## Related Code References

- iOS Implementation: `Session Proof/Services/ProjectSyncService.swift:acceptPendingInvitations()` (line ~1146)
- Firestore Service: `Session Proof/Services/FirestoreService.swift:findPendingInvitationsByEmail()` (line 156)
- Authentication: `Session Proof/Services/AuthenticationService.swift:signUp()` (line 168)
- Content View Trigger: `Session Proof/ContentView.swift` (line 86-94)
