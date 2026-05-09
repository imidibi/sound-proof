# Firebase Setup Instructions for Sound Proof

## Prerequisites

You need to complete these steps before the app will build:

## Step 1: Install Firebase SDK via Swift Package Manager

1. Open the project in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter this URL: `https://github.com/firebase/firebase-ios-sdk`
4. Click **Add Package**
5. Select these products to add:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
6. Click **Add Package**

## Step 2: Create Firebase Project

1. Go to https://console.firebase.google.com/
2. Click **"Add project"**
3. Project name: **"Sound Proof"**
4. Disable Google Analytics (or enable if you want it)
5. Click **"Create project"**

## Step 3: Add iOS App to Firebase

1. In your Firebase project console, click the iOS icon
2. **Bundle ID**: `salesdiver.Session-Proofsalesdiver.Session-Proofsalesdiver.Session-Proof`
3. **App nickname**: Sound Proof
4. Click **"Register app"**
5. **Download the `GoogleService-Info.plist` file**
6. Click "Continue to console" (skip SDK setup steps)

## Step 4: Add GoogleService-Info.plist to Xcode

1. Drag the downloaded `GoogleService-Info.plist` file into Xcode
2. Drop it into the **"Session Proof/Session Proof"** folder
3. In the dialog:
   - ✅ Check "Copy items if needed"
   - ✅ Select "Session Proof" target
   - Click **"Finish"**

## Step 5: Enable Firebase Services

### Enable Authentication:
1. In Firebase Console, go to **Build → Authentication**
2. Click **"Get started"**
3. Enable **"Email/Password"** sign-in method
4. Click **"Save"**

### Enable Firestore Database:
1. Go to **Build → Firestore Database**
2. Click **"Create database"**
3. Choose **"Start in test mode"** (for development)
4. Select a location (choose closest to you)
5. Click **"Enable"**

### Enable Cloud Storage:
1. Go to **Build → Storage**
2. Click **"Get started"**
3. Choose **"Start in test mode"** (for development)
4. Select same location as Firestore
5. Click **"Done"**

## Step 6: Update Security Rules (Important!)

### Firestore Rules:
Go to Firestore → Rules and replace with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User profiles
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }

    // Projects - producers can create, collaborators can read
    match /projects/{projectId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null &&
        (resource.data.ownerUserId == request.auth.uid ||
         request.auth.uid in resource.data.get('collaborators', []));

      // Songs
      match /songs/{songId} {
        allow read: if request.auth != null;
        allow write: if request.auth != null;

        // Mixes
        match /mixes/{mixId} {
          allow read: if request.auth != null;
          allow write: if request.auth != null;
        }
      }

      // Comments
      match /comments/{commentId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow update: if request.auth != null &&
          resource.data.authorId == request.auth.uid;
      }
    }
  }
}
```

### Storage Rules:
Go to Storage → Rules and replace with:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Project audio files
    match /projects/{projectId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

## Step 7: Build and Run!

1. Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)
2. Build the project: **Product → Build** (Cmd+B)
3. Run on your device or simulator

## Testing Authentication

1. Launch the app
2. You'll see the authentication screen
3. Click "Create an account"
4. Choose "Producer/Engineer" or "Client/Reviewer"
5. Fill in email, password, and name
6. Click "Create Account"

## How It Works

### For Producers:
1. Sign in as Producer
2. Create a project
3. Add songs
4. Upload mixes (they go to Firebase Storage)
5. Share the project code with clients

### For Clients:
1. Sign in as Client
2. Enter the project share code
3. Download and review mixes
4. Add comments and approvals

## Troubleshooting

### "Could not find GoogleService-Info.plist"
- Make sure the file is in the project navigator
- Check it's added to the "Session Proof" target
- Clean and rebuild

### "FirebaseApp.configure() failed"
- Verify GoogleService-Info.plist is correctly added
- Check the bundle ID matches: `salesdiver.Session-Proof`

### Authentication not working
- Check Authentication is enabled in Firebase Console
- Verify security rules are published
- Check network connection

## Cost Estimate

Firebase Free Tier (Spark Plan):
- ✅ Authentication: Unlimited users
- ✅ Firestore: 1GB storage, 50K reads/day
- ✅ Storage: 5GB storage, 1GB/day downloads
- ✅ Perfect for MVP and testing!

This should handle ~20-30 active projects with regular usage before needing to upgrade.
