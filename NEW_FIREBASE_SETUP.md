# New Firebase Project Setup Instructions

Your app is now configured for the new Firebase project: **approvl**

## Required Firebase Console Setup

Complete these steps in Firebase Console for the **approvl** project:

---

## 1. Enable Authentication

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select the **approvl** project
3. Click **Authentication** in the left sidebar
4. Click **Get started** (if not already enabled)
5. Click **Sign-in method** tab
6. Click **Email/Password**
7. Toggle **Enable** → ON
8. Click **Save**

---

## 2. Create Firestore Database

1. In Firebase Console, click **Firestore Database**
2. Click **Create database**
3. Choose **Start in production mode** (we'll add custom rules next)
4. Select a location (e.g., `us-central1` or closest to your users)
5. Click **Enable**

### Deploy Firestore Rules

1. Once database is created, click the **Rules** tab
2. Replace the default rules with the content from your `firestore.rules` file
3. Or copy/paste this:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper function to check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }

    // Helper function to check if user owns the project
    function isProjectOwner(projectId) {
      return isSignedIn() &&
             get(/databases/$(database)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid;
    }

    // Helper function to check if user is a reviewer on the project
    function isProjectReviewer(projectId) {
      return isSignedIn() &&
             exists(/databases/$(database)/documents/projects/$(projectId)/reviewers/$(request.auth.uid));
    }

    // Helper function to check if user is producer or studio
    function isProducer() {
      return isSignedIn() &&
             (get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'producer' ||
              get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'studio');
    }

    // Helper function to check if user is a member of the organization
    function isOrganizationMember(organizationId) {
      return isSignedIn() &&
             request.auth.uid in get(/databases/$(database)/documents/organizations/$(organizationId)).data.memberIds;
    }

    // Users collection
    match /users/{userId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && request.auth.uid == userId;
    }

    // Projects collection
    match /projects/{projectId} {
      allow get: if isSignedIn() &&
                    (isProjectOwner(projectId) || isProjectReviewer(projectId));
      allow list: if isSignedIn();
      allow create: if isSignedIn() && isProducer();
      allow update: if isSignedIn() && isProjectOwner(projectId);
      allow delete: if isSignedIn() && isProjectOwner(projectId);

      // Reviewers subcollection
      match /reviewers/{reviewerId} {
        allow read: if isSignedIn() &&
                       (isProjectOwner(projectId) ||
                        isProjectReviewer(projectId) ||
                        resource.data.email == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.email);
        allow create: if isSignedIn() && isProjectOwner(projectId);
        allow update: if isSignedIn() &&
                         (isProjectOwner(projectId) ||
                          (resource.data.email == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.email &&
                           request.resource.data.userId == request.auth.uid));
        allow delete: if isSignedIn() && isProjectOwner(projectId);
      }

      // Songs subcollection
      match /songs/{songId} {
        allow read: if isSignedIn() &&
                       (isProjectOwner(projectId) || isProjectReviewer(projectId));
        allow write: if isSignedIn() && isProjectOwner(projectId);

        // Mixes subcollection
        match /mixes/{mixId} {
          allow read: if isSignedIn() &&
                         (isProjectOwner(projectId) || isProjectReviewer(projectId));
          allow create, delete: if isSignedIn() && isProjectOwner(projectId);
          allow update: if isSignedIn() && isProjectOwner(projectId);
          allow update: if isSignedIn() &&
                           isProjectReviewer(projectId) &&
                           request.resource.data.diff(resource.data).affectedKeys().hasOnly(['approvalStatus']);

          // Approvals subcollection
          match /approvals/{approvalId} {
            allow read: if isSignedIn() &&
                           (isProjectOwner(projectId) || isProjectReviewer(projectId));
            allow create: if isSignedIn() && isProjectReviewer(projectId);
            allow update: if isSignedIn() &&
                             isProjectReviewer(projectId) &&
                             resource.data.reviewerUserId == request.auth.uid;
            allow delete: if isSignedIn() && isProjectOwner(projectId);
          }
        }
      }

      // Comments subcollection
      match /comments/{commentId} {
        allow read: if isSignedIn() &&
                       (isProjectOwner(projectId) || isProjectReviewer(projectId));
        allow create: if isSignedIn() &&
                         (isProjectOwner(projectId) || isProjectReviewer(projectId));
        allow update: if isSignedIn() &&
                         (request.auth.uid == resource.data.authorId || isProjectOwner(projectId));
        allow delete: if isSignedIn() &&
                         (request.auth.uid == resource.data.authorId || isProjectOwner(projectId));
      }
    }

    // Organizations collection
    match /organizations/{organizationId} {
      allow get: if isSignedIn() && isOrganizationMember(organizationId);
      allow list: if isSignedIn();
      allow create: if isSignedIn() && isProducer();
      allow update: if isSignedIn() && isOrganizationMember(organizationId);
      allow delete: if isSignedIn() && isOrganizationMember(organizationId);
    }
  }
}
```

4. Click **Publish**

---

## 3. Enable Cloud Storage

1. Click **Storage** in the left sidebar
2. Click **Get started**
3. Start in **production mode** (we'll add custom rules next)
4. Use the same location as Firestore
5. Click **Done**

### Deploy Storage Rules

1. Click the **Rules** tab in Storage
2. Replace the default rules with the content from your `storage.rules` file
3. Or copy/paste this:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function isSignedIn() {
      return request.auth != null;
    }

    function isProjectOwner(projectId) {
      return isSignedIn() &&
             firestore.get(/databases/(default)/documents/projects/$(projectId)).data.ownerUserId == request.auth.uid;
    }

    function isProjectReviewer(projectId) {
      return isSignedIn() &&
             firestore.exists(/databases/(default)/documents/projects/$(projectId)/reviewers/$(request.auth.uid));
    }

    // Audio files for mixes
    match /projects/{projectId}/mixes/{mixId}/{fileName} {
      allow read: if isSignedIn() &&
                     (isProjectOwner(projectId) || isProjectReviewer(projectId));
      allow write: if isSignedIn() && isProjectOwner(projectId);
      allow delete: if isSignedIn() && isProjectOwner(projectId);
    }

    // Voice note comments
    match /projects/{projectId}/comments/{commentId}/{fileName} {
      allow read: if isSignedIn() &&
                     (isProjectOwner(projectId) || isProjectReviewer(projectId));
      allow write: if isSignedIn() &&
                      (isProjectOwner(projectId) || isProjectReviewer(projectId));
      allow delete: if isSignedIn() &&
                       (isProjectOwner(projectId) || isProjectReviewer(projectId));
    }

    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

4. Click **Publish**

---

## 4. Test the Setup

### In Xcode:

1. Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
2. Build and run the app
3. Create a new account as producer (use a test email like `testproducer@example.com`)
4. Create a project, add a song, upload a mix
5. Invite a reviewer (use another test email like `testreviewer@example.com`)
6. Sign out and create the reviewer account
7. Verify the reviewer can see the project

### Expected Console Output:

```
🔐 Login successful for user: [userId]
📊 Starting full sync...
✅ Sync complete
```

No bundle ID warnings, no permission errors.

---

## 5. Verify in Firebase Console

After testing, check:

1. **Authentication → Users**: Should see your test accounts
2. **Firestore Database → Data**: Should see:
   - `users` collection with user documents
   - `projects` collection with project documents
   - Nested `reviewers`, `songs`, `mixes` subcollections
3. **Storage → Files**: Should see uploaded audio files under `projects/`

---

## Summary Checklist

- [ ] Enable Email/Password authentication
- [ ] Create Firestore database
- [ ] Deploy Firestore rules
- [ ] Enable Cloud Storage
- [ ] Deploy Storage rules
- [ ] Build and run app in Xcode
- [ ] Create test producer account
- [ ] Create test project and upload mix
- [ ] Invite test reviewer
- [ ] Create test reviewer account
- [ ] Verify reviewer can access project
- [ ] Check Firebase Console data

---

## Notes

- This is a completely fresh Firebase project with no old data
- All user accounts will need to be created from scratch
- Perfect clean slate for beta testing
- The old `sound-proof-6096d` project is still available if needed

---

## Need Help?

If you encounter any errors during setup or testing, check the Xcode console output and let me know what's happening.
