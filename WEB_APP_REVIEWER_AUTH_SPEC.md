# Web App Reviewer Authentication & Access Specification

**Version:** 2.0
**Date:** June 2026
**Purpose:** Technical specification for implementing reviewer-only authentication and project access in the web app, matching iOS/Mac app behavior exactly

---

## Table of Contents
1. [Overview](#overview)
2. [Authentication Flow](#authentication-flow)
3. [Invitation System](#invitation-system)
4. [Data Model](#data-model)
5. [User Roles & Permissions](#user-roles--permissions)
6. [API Operations](#api-operations)
7. [Project Discovery](#project-discovery)
8. [Implementation Guide](#implementation-guide)
9. [Security Rules](#security-rules)

---

## Overview

The web app serves as an **approver-only access path** to Session Proof. It uses the same authentication system as the iOS/Mac app, allowing invited reviewers to:

1. **Sign up** using their invited email address
2. **Automatically accept** any pending invitations during account creation
3. **Access all projects** they've been invited to as a reviewer
4. **View mixes, comment, and set their personal approval** on those projects

**Key Principle:** The web app shares the exact same Firebase backend, authentication system, and data structures as the iOS/Mac app. There is no separate guest access system - reviewers are real Firebase Auth users with full accounts.

---

## Authentication Flow

### High-Level Flow

```
Producer invites reviewer via email
    ↓
Invitation creates pending_invitations document
    ↓
Reviewer receives email, clicks link to web app
    ↓
Reviewer signs up with email + password
    ↓
Backend automatically checks for pending invitations
    ↓
Backend links reviewer's new userId to invitation
    ↓
Pending invitation document is deleted
    ↓
Reviewer can now access all projects they're invited to
```

### Detailed Sign-Up Process

When a new user signs up on the web app:

1. **Create Firebase Auth Account**
   ```typescript
   const userCredential = await createUserWithEmailAndPassword(
     auth,
     email.toLowerCase().trim(),
     password
   );
   const userId = userCredential.user.uid;
   ```

2. **Create User Profile in Firestore**
   ```typescript
   await setDoc(doc(db, 'users', userId), {
     email: email.toLowerCase().trim(),
     displayName: displayName,
     role: 'artist',  // Web users are always 'artist' role
     createdAt: Timestamp.now()
   });
   ```

3. **Check for Pending Invitations**
   ```typescript
   // This happens automatically after account creation
   await acceptPendingInvitations(userId, email);
   ```

4. **Sign In and Load Projects**
   ```typescript
   // After invitations are accepted, load user's projects
   const projects = await getProjectsWhereUserIsReviewer(userId, email);
   ```

### Sign-In Process

For existing users signing in:

1. **Authenticate with Firebase**
   ```typescript
   const userCredential = await signInWithEmailAndPassword(
     auth,
     email.toLowerCase().trim(),
     password
   );
   ```

2. **Load User Profile**
   ```typescript
   const userId = userCredential.user.uid;
   const userDoc = await getDoc(doc(db, 'users', userId));
   const userData = userDoc.data();
   ```

3. **Load Projects**
   ```typescript
   const projects = await getProjectsWhereUserIsReviewer(userId, email);
   ```

---

## Invitation System

### How Invitations Work

When a producer invites a reviewer in the iOS/Mac app:

1. **Producer enters reviewer email and name**
2. **iOS app creates two Firestore documents:**

   **A) Reviewer Document** (UUID-based ID)
   ```
   Path: /projects/{projectId}/reviewers/{reviewerUUID}
   ```
   ```typescript
   {
     displayName: "John Doe",
     email: "john@example.com",  // lowercase
     role: "reviewer",
     inviteStatus: "sent",
     userId: null,  // Will be filled when user signs up
     invitedAt: Timestamp,
     createdAt: Timestamp,
     isKeyApprover: false
   }
   ```

   **B) Pending Invitation Document** (email-based ID)
   ```
   Path: /pending_invitations/{email}
   ```
   ```typescript
   {
     inviteeEmail: "john@example.com",  // lowercase
     projectId: "abc123",
     reviewerId: "uuid-of-reviewer-doc",  // References document A
     displayName: "John Doe",
     createdAt: Timestamp
   }
   ```

3. **Producer sends invitation email** (outside of Firebase - via email service)

### Accepting Invitations

When the invited user signs up:

1. **Query pending_invitations collection by email:**
   ```typescript
   const inviteDoc = await getDoc(
     doc(db, 'pending_invitations', email.toLowerCase())
   );
   ```

2. **For each pending invitation found:**

   a. **Update the UUID-based reviewer document** with userId:
   ```typescript
   await updateDoc(
     doc(db, 'projects', projectId, 'reviewers', reviewerId),
     {
       userId: currentUserId,
       inviteStatus: 'accepted',
       acceptedAt: Timestamp.now()
     }
   );
   ```

   b. **Create userId-based reviewer document** (for security rules):
   ```typescript
   await setDoc(
     doc(db, 'projects', projectId, 'reviewers', currentUserId),
     {
       email: email.toLowerCase(),
       userId: currentUserId,
       inviteStatus: 'accepted',
       acceptedAt: Timestamp.now(),
       primaryReviewerId: reviewerId  // Reference to UUID document
     }
   );
   ```

   c. **Delete the pending invitation document:**
   ```typescript
   await deleteDoc(
     doc(db, 'pending_invitations', email.toLowerCase())
   );
   ```

### Why Two Reviewer Documents?

The iOS/Mac app creates **two reviewer documents per user**:

1. **UUID-based document** (`/reviewers/{uuid}`)
   - Primary document with all reviewer data
   - Document ID is a UUID generated by iOS app
   - Used for display and data management

2. **userId-based document** (`/reviewers/{userId}`)
   - Security document for Firestore rules
   - Document ID is the Firebase Auth UID
   - Allows `isProjectReviewer()` rule to check: `exists(/reviewers/$(request.auth.uid))`
   - Contains `primaryReviewerId` field pointing to UUID document

**Important:** The web app must maintain this same pattern when accepting invitations.

---

## Data Model

### User Document

**Location:** `/users/{userId}`

```typescript
interface User {
  email: string;                    // lowercase
  displayName: string;
  role: 'artist' | 'producer' | 'studio';
  createdAt: Timestamp;

  // Optional fields (not used by web reviewers)
  phone?: string;
  title?: string;
  organizationId?: string;
  organizationName?: string;
  subscriptionTier?: string;
  subscriptionStatus?: string;
  // ... other subscription fields
}
```

**For web app reviewers:**
- `role` is always `"artist"`
- Only `email`, `displayName`, `role`, and `createdAt` are required

### Reviewer Document (UUID-based)

**Location:** `/projects/{projectId}/reviewers/{reviewerUUID}`

```typescript
interface Reviewer {
  displayName: string;
  email: string;                    // lowercase
  userId?: string;                  // Firebase Auth UID (null until accepted)
  role: 'reviewer';                 // Always 'reviewer'
  inviteStatus: 'sent' | 'accepted' | 'declined';
  isKeyApprover: boolean;           // Only ONE per project can be true
  createdAt: Timestamp;
  invitedAt?: Timestamp;
  acceptedAt?: Timestamp;
}
```

### Reviewer Document (userId-based)

**Location:** `/projects/{projectId}/reviewers/{userId}`

```typescript
interface ReviewerByUserId {
  email: string;                    // lowercase
  userId: string;                   // Firebase Auth UID
  inviteStatus: 'accepted';
  acceptedAt: Timestamp;
  primaryReviewerId: string;        // UUID of the main reviewer document
}
```

### Pending Invitation Document

**Location:** `/pending_invitations/{email}`

```typescript
interface PendingInvitation {
  inviteeEmail: string;             // lowercase (same as document ID)
  projectId: string;
  reviewerId: string;               // UUID of reviewer document
  displayName: string;
  createdAt: Timestamp;
}
```

**Note:** Document ID is the email address (lowercase). This allows easy lookup during signup.

### Project Document

**Location:** `/projects/{projectId}`

```typescript
interface Project {
  name: string;
  clientName?: string;
  ownerUserId: string;              // Firebase Auth UID of producer
  status: 'Active' | 'Archived';
  shareCode: string;                // 6-character code (not used for invitations)
  createdAt: Timestamp;
  updatedAt: Timestamp;
  isArchived?: boolean;
}
```

---

## User Roles & Permissions

### Role: Artist (Web Reviewer)

**What they CAN do:**
- ✅ View projects they're invited to
- ✅ View songs in those projects (except archived songs)
- ✅ View mixes in those songs
- ✅ Play audio from mixes
- ✅ Read all comments on mixes
- ✅ Create comments on mixes
- ✅ **Set their personal approval opinion** (In Review / Approved / Changes Requested)
- ✅ See all other reviewers' approval opinions
- ✅ See the mix's final approval status (read-only)

**What they CANNOT do:**
- ❌ Create, edit, or delete projects
- ❌ Create, edit, or delete songs
- ❌ Upload, edit, or delete mixes
- ❌ Change mix's final approval status (only producer/key approver can)
- ❌ Invite or remove other reviewers
- ❌ See archived songs
- ❌ Delete or edit their own comments (read-only after creation in web)
- ❌ Access projects they're not invited to

### Role: Producer

**Note:** Producers should NOT use the web app. The web app is reviewer-only. Producers use the iOS/Mac app.

### Key Approver

A reviewer can be designated as a **Key Approver** by the producer:
- Only ONE key approver per project
- Identified by `reviewer.isKeyApprover === true`
- Key approvers can set the mix's final approval status (like producers)
- **Web app should show key approver badge** but not allow changing final status

---

## API Operations

### 1. Sign Up New User

```typescript
async function signUpReviewer(
  email: string,
  password: string,
  displayName: string
): Promise<string> {
  // Normalize email
  const normalizedEmail = email.toLowerCase().trim();

  // Create Firebase Auth account
  const userCredential = await createUserWithEmailAndPassword(
    auth,
    normalizedEmail,
    password
  );

  const userId = userCredential.user.uid;

  // Create user profile
  await setDoc(doc(db, 'users', userId), {
    email: normalizedEmail,
    displayName: displayName,
    role: 'artist',
    createdAt: Timestamp.now()
  });

  // Accept any pending invitations
  await acceptPendingInvitations(userId, normalizedEmail);

  return userId;
}
```

### 2. Accept Pending Invitations

```typescript
async function acceptPendingInvitations(
  userId: string,
  userEmail: string
): Promise<number> {
  const normalizedEmail = userEmail.toLowerCase().trim();

  // Check for pending invitation
  const inviteRef = doc(db, 'pending_invitations', normalizedEmail);
  const inviteDoc = await getDoc(inviteRef);

  if (!inviteDoc.exists()) {
    console.log('No pending invitations found');
    return 0;
  }

  const inviteData = inviteDoc.data();
  const projectId = inviteData.projectId;
  const reviewerId = inviteData.reviewerId;

  // Update UUID-based reviewer document
  await updateDoc(
    doc(db, 'projects', projectId, 'reviewers', reviewerId),
    {
      userId: userId,
      inviteStatus: 'accepted',
      acceptedAt: Timestamp.now()
    }
  );

  // Create userId-based reviewer document
  await setDoc(
    doc(db, 'projects', projectId, 'reviewers', userId),
    {
      email: normalizedEmail,
      userId: userId,
      inviteStatus: 'accepted',
      acceptedAt: Timestamp.now(),
      primaryReviewerId: reviewerId
    }
  );

  // Delete pending invitation
  await deleteDoc(inviteRef);

  console.log(`✅ Accepted invitation for project: ${projectId}`);
  return 1;
}
```

### 3. Sign In Existing User

```typescript
async function signInReviewer(
  email: string,
  password: string
): Promise<User> {
  const normalizedEmail = email.toLowerCase().trim();

  const userCredential = await signInWithEmailAndPassword(
    auth,
    normalizedEmail,
    password
  );

  const userId = userCredential.user.uid;

  // Load user profile
  const userDoc = await getDoc(doc(db, 'users', userId));

  if (!userDoc.exists()) {
    throw new Error('User profile not found');
  }

  const userData = userDoc.data();

  return {
    id: userId,
    email: userData.email,
    displayName: userData.displayName,
    role: userData.role,
    createdAt: userData.createdAt.toDate()
  };
}
```

### 4. Get Projects Where User Is Reviewer

```typescript
async function getProjectsWhereUserIsReviewer(
  userId: string,
  userEmail: string
): Promise<Project[]> {
  console.log(`🔍 Finding projects for userId: ${userId}`);

  // Use collection group query to find all reviewer documents
  // where userId matches current user
  const reviewersQuery = query(
    collectionGroup(db, 'reviewers'),
    where('userId', '==', userId)
  );

  const reviewersSnapshot = await getDocs(reviewersQuery);

  console.log(`📧 Found ${reviewersSnapshot.docs.length} reviewer records`);

  const projectIds = new Set<string>();
  const projects: Project[] = [];

  // Extract unique project IDs from reviewer document paths
  for (const reviewerDoc of reviewersSnapshot.docs) {
    // Path format: projects/{projectId}/reviewers/{reviewerId}
    const pathParts = reviewerDoc.ref.path.split('/');

    if (pathParts.length >= 2 && pathParts[0] === 'projects') {
      const projectId = pathParts[1];

      // Skip if already processed
      if (projectIds.has(projectId)) {
        continue;
      }

      projectIds.add(projectId);

      // Fetch project document
      const projectDoc = await getDoc(doc(db, 'projects', projectId));

      if (projectDoc.exists()) {
        const projectData = projectDoc.data();

        // Skip archived projects
        if (projectData.isArchived === true) {
          console.log(`⏭️ Skipping archived project: ${projectId}`);
          continue;
        }

        projects.push({
          id: projectId,
          name: projectData.name,
          clientName: projectData.clientName,
          ownerUserId: projectData.ownerUserId,
          status: projectData.status,
          shareCode: projectData.shareCode,
          createdAt: projectData.createdAt.toDate(),
          updatedAt: projectData.updatedAt.toDate()
        });

        console.log(`✅ Added project: ${projectData.name}`);
      }
    }
  }

  console.log(`📦 Found ${projects.length} active projects`);
  return projects;
}
```

### 5. Get Songs for Project

```typescript
async function getSongsForProject(projectId: string): Promise<Song[]> {
  const songsRef = collection(db, 'projects', projectId, 'songs');
  const songsSnapshot = await getDocs(songsRef);

  const songs: Song[] = [];

  for (const songDoc of songsSnapshot.docs) {
    const songData = songDoc.data();

    // Skip archived songs (reviewers can't see them)
    if (songData.isArchived === true) {
      continue;
    }

    songs.push({
      id: songDoc.id,
      name: songData.name,
      artist: songData.artist || '',
      notes: songData.notes || '',
      status: songData.status,
      sortOrder: songData.sortOrder,
      createdAt: songData.createdAt.toDate(),
      updatedAt: songData.updatedAt.toDate()
    });
  }

  return songs;
}
```

### 6. Get Mixes for Song

```typescript
async function getMixesForSong(
  projectId: string,
  songId: string
): Promise<Mix[]> {
  const mixesRef = collection(
    db,
    'projects', projectId,
    'songs', songId,
    'mixes'
  );

  const mixesSnapshot = await getDocs(mixesRef);

  const mixes: Mix[] = [];

  for (const mixDoc of mixesSnapshot.docs) {
    const mixData = mixDoc.data();

    // Skip deleted mixes
    if (mixData.isDeleted === true) {
      continue;
    }

    mixes.push({
      id: mixDoc.id,
      name: mixData.name,
      versionNumber: mixData.versionNumber,
      cloudURL: mixData.cloudURL,
      duration: mixData.duration,
      sampleRate: mixData.sampleRate,
      channels: mixData.channels,
      approvalStatus: mixData.approvalStatus,
      notes: mixData.notes || '',
      uploadedAt: mixData.uploadedAt.toDate(),
      updatedAt: mixData.updatedAt.toDate()
    });
  }

  return mixes;
}
```

### 7. Real-Time Project Listener

```typescript
function listenToUserProjects(
  userId: string,
  callback: (projects: Project[]) => void
): () => void {
  // Use collection group query with real-time listener
  const reviewersQuery = query(
    collectionGroup(db, 'reviewers'),
    where('userId', '==', userId)
  );

  const unsubscribe = onSnapshot(reviewersQuery, async (snapshot) => {
    const projectIds = new Set<string>();
    const projects: Project[] = [];

    for (const reviewerDoc of snapshot.docs) {
      const pathParts = reviewerDoc.ref.path.split('/');

      if (pathParts.length >= 2 && pathParts[0] === 'projects') {
        const projectId = pathParts[1];

        if (!projectIds.has(projectId)) {
          projectIds.add(projectId);

          const projectDoc = await getDoc(doc(db, 'projects', projectId));

          if (projectDoc.exists()) {
            const projectData = projectDoc.data();

            if (projectData.isArchived !== true) {
              projects.push({
                id: projectId,
                name: projectData.name,
                clientName: projectData.clientName,
                ownerUserId: projectData.ownerUserId,
                status: projectData.status,
                shareCode: projectData.shareCode,
                createdAt: projectData.createdAt.toDate(),
                updatedAt: projectData.updatedAt.toDate()
              });
            }
          }
        }
      }
    }

    callback(projects);
  });

  return unsubscribe;
}
```

---

## Project Discovery

### How Web Reviewers Find Their Projects

Unlike producers who have an `ownerUserId` field on projects, reviewers don't have a direct index. The web app must use **collection group queries** to find projects:

**Step-by-step:**

1. **Query all reviewer documents** with current user's `userId`:
   ```typescript
   collectionGroup('reviewers').where('userId', '==', currentUserId)
   ```

2. **Extract project IDs** from document paths:
   ```typescript
   // Document path: projects/{projectId}/reviewers/{reviewerId}
   const pathParts = doc.ref.path.split('/');
   const projectId = pathParts[1];
   ```

3. **Fetch each unique project document**

4. **Filter out archived projects** (reviewers can't see archived)

5. **Return list of projects**

**Performance Note:** Collection group queries are indexed and performant. The iOS/Mac app uses the same approach.

---

## Implementation Guide

### Phase 1: Authentication

1. **Create sign-up form**
   - Email input (will be normalized to lowercase)
   - Password input (minimum 6 characters per Firebase requirements)
   - Display name input
   - "Create Account" button

2. **Implement signUpReviewer() function**
   - Create Firebase Auth account
   - Create Firestore user profile with role 'artist'
   - Call acceptPendingInvitations()
   - Redirect to projects list

3. **Create sign-in form**
   - Email input
   - Password input
   - "Sign In" button
   - "Forgot Password" link

4. **Implement signInReviewer() function**
   - Authenticate with Firebase
   - Load user profile
   - Redirect to projects list

5. **Implement password reset**
   ```typescript
   await sendPasswordResetEmail(auth, email.toLowerCase().trim());
   ```

### Phase 2: Invitation Acceptance

1. **Implement acceptPendingInvitations() function**
   - Query pending_invitations by email
   - Update UUID-based reviewer document
   - Create userId-based reviewer document
   - Delete pending invitation document

2. **Call automatically after signup**

3. **Show success message** if invitations were accepted

### Phase 3: Project Discovery

1. **Implement getProjectsWhereUserIsReviewer() function**
   - Use collection group query
   - Extract project IDs from paths
   - Fetch project documents
   - Filter archived projects

2. **Create projects list UI**
   - Show project name and client name
   - Click to open project detail

3. **Implement real-time listener** (optional but recommended)

### Phase 4: Project Content

1. **Implement getSongsForProject()**
   - Filter out archived songs

2. **Implement getMixesForSong()**
   - Filter out deleted mixes

3. **Create navigation**
   - Project → Songs → Mixes

4. **Implement audio player** (see WEB_APP_SPECIFICATION.md)

5. **Implement comments** (see WEB_APP_SPECIFICATION.md)

6. **Implement approvals** (see WEB_APP_APPROVAL_SPEC.md)

---

## Security Rules

The corrected Firestore rules already support this authentication flow:

### Users Collection

```javascript
match /users/{userId} {
  allow read: if isSignedIn();
  allow write: if isSignedIn() && request.auth.uid == userId;
}
```

### Pending Invitations Collection

```javascript
match /pending_invitations/{email} {
  allow read: if true;  // Anyone can check for invitations
  allow write, delete: if isSignedIn();
}
```

### Reviewers Subcollection

```javascript
match /reviewers/{reviewerId} {
  allow get: if isSignedIn() &&
                (get(/databases/$(database)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid ||
                 isProjectReviewer(projectId) ||
                 reviewerId == request.auth.uid);

  allow list: if isSignedIn();

  allow create: if isSignedIn() &&
                   (get(/databases/$(database)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid ||
                    reviewerId == request.auth.uid);

  allow update: if isSignedIn() &&
                   (get(/databases/$(database)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid ||
                    reviewerId == request.auth.uid ||
                    (resource.data.email == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.email &&
                     request.resource.data.userId == request.auth.uid));

  allow delete: if isSignedIn() &&
                   get(/databases/$(database)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid;
}
```

**Key Points:**
- `allow list: if isSignedIn()` allows collection group queries
- Update rule allows reviewers to set their own `userId` when accepting invitations
- Users can update reviewer documents where `reviewerId == request.auth.uid` (userId-based docs)

### Collection Group Query Rule

```javascript
match /{path=**}/reviewers/{reviewerId} {
  allow read: if isSignedIn() &&
                 (reviewerId == request.auth.uid ||
                  resource.data.userId == request.auth.uid);
}
```

This allows reviewers to query all `reviewers` subcollections where their `userId` matches.

---

## Testing Checklist

### Authentication

- [ ] User can sign up with email and password
- [ ] Email is normalized to lowercase
- [ ] User profile is created in Firestore with role 'artist'
- [ ] User can sign in with email and password
- [ ] User can reset password
- [ ] Error messages display correctly for invalid credentials

### Invitation Acceptance

- [ ] Pending invitation document is found by email
- [ ] UUID-based reviewer document is updated with userId
- [ ] userId-based reviewer document is created
- [ ] Pending invitation document is deleted
- [ ] Multiple invitations can be accepted in one signup
- [ ] Acceptance works even if user already exists (sign in after invitation)

### Project Discovery

- [ ] Collection group query finds all projects user is reviewer on
- [ ] Archived projects are filtered out
- [ ] Project list displays correctly
- [ ] Real-time updates work when new projects are added

### Project Access

- [ ] Reviewer can view songs in project
- [ ] Archived songs are hidden from reviewer
- [ ] Reviewer can view mixes in song
- [ ] Deleted mixes are hidden from reviewer
- [ ] Reviewer can play audio from mixes
- [ ] Reviewer can create comments
- [ ] Reviewer can set their personal approval opinion
- [ ] Reviewer cannot change mix's final approval status

### Security

- [ ] Reviewer cannot access projects they're not invited to
- [ ] Reviewer cannot create, edit, or delete projects
- [ ] Reviewer cannot create, edit, or delete songs
- [ ] Reviewer cannot upload, edit, or delete mixes
- [ ] Reviewer cannot invite or remove other reviewers

---

## Summary

**Key Implementation Points:**

1. **Authentication:** Use standard Firebase Auth - no custom tokens or anonymous auth
2. **User Role:** Always create web users with role `'artist'`
3. **Invitation Acceptance:** Automatically called after signup, updates two reviewer documents
4. **Project Discovery:** Use collection group query on `reviewers` subcollection
5. **Permissions:** Reviewers are read-only except for comments and their personal approvals
6. **Data Sync:** All data is real-time synced with iOS/Mac apps through shared Firestore

**What Makes This Different From Guest Access:**

- ❌ No guest codes
- ❌ No anonymous authentication
- ❌ No custom claims
- ❌ No single-mix access
- ✅ Real Firebase Auth accounts
- ✅ Email/password authentication
- ✅ Access to all invited projects
- ✅ Same permissions as iOS/Mac reviewers

**Critical Firebase Operations:**

1. `createUserWithEmailAndPassword()` - Create auth account
2. `setDoc(users/{userId})` - Create user profile
3. `getDoc(pending_invitations/{email})` - Check for invitations
4. `updateDoc(reviewers/{uuid})` - Link userId to invitation
5. `setDoc(reviewers/{userId})` - Create userId-based document
6. `deleteDoc(pending_invitations/{email})` - Delete accepted invitation
7. `collectionGroup('reviewers').where('userId', '==', uid)` - Find projects

---

**End of Specification**

This specification provides everything needed to implement reviewer authentication and project access in the web app, matching the iOS/Mac app behavior exactly!
