# Firebase Rules - Deploy Immediately

## Critical Fix for Reviewer Invitations

The Firestore rules have been updated to allow reviewers to accept invitations. You need to deploy these updated rules to Firebase Console **right now**.

---

## How to Deploy

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select the **approvl** project
3. Click **Firestore Database** → **Rules** tab
4. **Replace ALL rules** with the content below
5. Click **Publish**

---

## Updated Firestore Rules

Copy and paste these rules into Firebase Console:

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
      // Allow reading individual projects
      allow get: if isSignedIn() &&
                    (isProjectOwner(projectId) || isProjectReviewer(projectId));
      // Allow listing/querying projects (query filter ensures only user's projects are returned)
      allow list: if isSignedIn();
      allow create: if isSignedIn() && isProducer();
      allow update: if isSignedIn() && isProjectOwner(projectId);
      allow delete: if isSignedIn() && isProjectOwner(projectId);

      // Reviewers subcollection
      match /reviewers/{reviewerId} {
        allow read: if isSignedIn() &&
                       (isProjectOwner(projectId) ||
                        isProjectReviewer(projectId) ||
                        reviewerId == request.auth.uid);
        allow create: if isSignedIn() &&
                         (isProjectOwner(projectId) ||
                          reviewerId == request.auth.uid);
        allow update: if isSignedIn() &&
                         (isProjectOwner(projectId) ||
                          reviewerId == request.auth.uid);
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
          // Allow project owner to update any field
          allow update: if isSignedIn() && isProjectOwner(projectId);
          // Allow reviewers to update only the approvalStatus field
          allow update: if isSignedIn() &&
                           isProjectReviewer(projectId) &&
                           request.resource.data.diff(resource.data).affectedKeys().hasOnly(['approvalStatus']);

          // Approvals subcollection
          match /approvals/{approvalId} {
            allow read: if isSignedIn() &&
                           (isProjectOwner(projectId) || isProjectReviewer(projectId));
            // Allow reviewers to create their own approval records
            allow create: if isSignedIn() && isProjectReviewer(projectId);
            // Allow reviewers to update only their own approval records
            allow update: if isSignedIn() &&
                             isProjectReviewer(projectId) &&
                             resource.data.reviewerUserId == request.auth.uid;
            // Only project owner can delete approvals
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
      // Allow reading individual organizations
      allow get: if isSignedIn() && isOrganizationMember(organizationId);
      // Allow querying organizations (query filter ensures only user's orgs are returned)
      allow list: if isSignedIn();
      allow create: if isSignedIn() && isProducer();
      allow update: if isSignedIn() && isOrganizationMember(organizationId);
      allow delete: if isSignedIn() && isOrganizationMember(organizationId);
    }
  }
}
```

---

## What Changed

**Old reviewer rules** (lines 53-64):
- Required fetching user document to check email match
- Only allowed owner or invited user (by email) to update
- Created circular permission dependencies

**New reviewer rules**:
- ✅ Allow read if `reviewerId == request.auth.uid` (userId-based document)
- ✅ Allow create if `reviewerId == request.auth.uid` (reviewers can create their userId document)
- ✅ Allow update if `reviewerId == request.auth.uid` (reviewers can link their userId)
- ✅ Simpler, no circular dependencies

This allows the invitation acceptance flow to work:
1. Producer invites reviewer by email → creates UUID-based document
2. Reviewer signs up/logs in → gets Firebase Auth userId
3. App finds pending invitation by searching email
4. **App creates userId-based document** → ✅ NOW ALLOWED
5. Reviewer can access project → ✅ WORKS

---

## After Deploying

1. Delete the test user `testartist@example.com` from Firebase Auth
2. Delete the Firestore user document for `ukfZierUMvOEZniWkvURpEGcZeN2`
3. Re-invite `testartist@example.com` from the producer account
4. Sign up as testartist again
5. Projects should now appear ✅

---

## Deploy Storage Rules Too

While you're in Firebase Console, also deploy the storage rules:

1. Click **Storage** → **Rules** tab
2. Replace with content from `storage.rules` file (already provided in NEW_FIREBASE_SETUP.md)
3. Click **Publish**
