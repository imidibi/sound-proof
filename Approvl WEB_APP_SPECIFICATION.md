# Approvl Web Guest Access - Technical Specification

**Version:** 1.0
**Date:** June 2026
**Purpose:** Comprehensive specification for building a web companion app for Approvl iOS app

---

## Table of Contents
1. [Overview](#overview)
2. [User Stories](#user-stories)
3. [Data Models](#data-models)
4. [Firebase Structure](#firebase-structure)
5. [Authentication & Guest Codes](#authentication--guest-codes)
6. [Core Features](#core-features)
7. [Technical Stack](#technical-stack)
8. [Security Considerations](#security-considerations)
9. [Implementation Phases](#implementation-phases)

---

## Overview

Approvl is an iOS music collaboration app where producers upload mixes and get feedback from reviewers. This web app will allow **guest users** to access specific mixes via shareable codes to:
- Listen to audio with waveform visualization
- Leave timestamped comments
- View approval status (read-only for guests)

**Key Constraint:** Guests should have limited, read-only access (except for commenting) and should only see the specific mix they're invited to view.

---

## User Stories

### As a Producer (iOS App)
- I can generate a guest code for a specific mix
- I can share this code with anyone (clients, collaborators, friends)
- I can revoke guest codes
- I can see who accessed my mix via guest codes

### As a Guest (Web App)
- I can enter a guest code and immediately access a mix
- I can listen to the audio with a visual waveform
- I can click on the waveform to leave timestamped comments
- I can see existing comments from other reviewers
- I can see the approval status (approved/pending/changes requested)
- I do NOT need to create an account or download an app

---

## Data Models

### Project
```typescript
interface Project {
  id: string;  // Firestore document ID
  name: string;

  // Basic Information
  artistName?: string;
  producerName?: string;
  studioName?: string;
  genre?: string;
  releaseDate?: Date;

  // Ownership
  ownerUserID: string;  // User who created the project
  organizationId?: string;

  // Workflow
  workflowStage?: 'Tracking' | 'Editing' | 'Mixing' | 'Mastering' | 'Review' | 'Approved' | 'Released' | 'Archived';
  status: 'Draft' | 'In Review' | 'Revisions Needed' | 'Approved' | 'Archived';

  // Dates
  createdAt: Date;
  updatedAt: Date;

  // Notes
  notes?: string;

  // Sharing
  shareCode?: string;  // 6-character code for sharing entire project

  // Archive
  isArchived: boolean;
  archivedAt?: Date;
}
```

### Song
```typescript
interface Song {
  id: string;  // Firestore document ID
  name: string;
  artist?: string;
  notes?: string;
  status: 'Draft' | 'In Progress' | 'Mixing Complete' | 'Shared' | 'In Review' | 'Revisions Needed' | 'Approved' | 'Archived';
  createdAt: Date;
  updatedAt: Date;
  sortOrder: number;

  // Archive
  isArchived: boolean;
  archivedAt?: Date;
}
```

### Mix
```typescript
interface Mix {
  id: string;  // Firestore document ID
  name: string;
  versionNumber: number;

  // Audio file
  cloudURL: string;  // Firebase Storage download URL
  duration: number;  // In seconds
  sampleRate: number;  // e.g., 44100
  channels: number;  // e.g., 2 for stereo
  bitrate?: number;  // In kbps
  format?: string;  // e.g., 'mp3', 'wav', 'm4a'

  // Status
  approvalStatus: 'Draft' | 'Shared' | 'In Review' | 'Approved' | 'Superseded';

  // Metadata
  createdAt: Date;
  notes?: string;
  waveformCache?: string;  // Base64 encoded waveform data (optional)

  // Upload tracking
  isUploaded: boolean;
  uploadedAt?: Date;
  lastModifiedAt: Date;
}
```

### Comment
```typescript
interface Comment {
  id: string;  // Firestore document ID
  timestamp: number;  // Position in audio (seconds)
  endTimestamp?: number;  // For range comments
  text: string;

  // Voice notes (optional - may not implement in web initially)
  voiceNoteCloudURL?: string;

  // Status
  status: 'Open' | 'Resolved' | 'Rejected' | 'Converted to Task';

  // Author
  authorID: string;
  authorName: string;

  // Dates
  createdAt: Date;
}
```

### Approval
```typescript
interface Approval {
  id: string;  // Firestore document ID
  status: 'In Review' | 'Approved' | 'Changes Requested';
  note?: string;
  createdAt: Date;
  updatedAt: Date;

  // Reviewer reference (in reviewers subcollection)
  reviewerId: string;
}
```

### Reviewer
```typescript
interface Reviewer {
  id: string;  // Firestore document ID
  userId: string;  // Reference to users collection
  email: string;
  displayName: string;
  role: 'Reviewer' | 'Producer';
  isKeyApprover: boolean;  // Can approve/reject

  // Invitation
  inviteStatus: 'Pending' | 'Accepted' | 'Declined';
  createdAt: Date;
  acceptedAt?: Date;
}
```

### GuestAccess (NEW - for web app)
```typescript
interface GuestAccess {
  id: string;  // Firestore document ID
  code: string;  // 8-character unique code

  // Access scope
  projectId: string;
  songId: string;
  mixId: string;

  // Permissions
  canComment: boolean;  // Default: true
  canViewOtherComments: boolean;  // Default: true

  // Creator & metadata
  createdBy: string;  // User ID who created the code
  createdAt: Date;
  expiresAt?: Date;  // Optional expiration

  // Usage tracking
  isActive: boolean;
  lastAccessedAt?: Date;
  accessCount: number;

  // Guest info (optional)
  guestName?: string;  // Can be set when guest enters
  guestEmail?: string;
}
```

---

## Firebase Structure

### Firestore Collections

```
/users/{userId}
  - email: string
  - displayName: string
  - role: 'producer' | 'artist' | 'studio'
  - createdAt: timestamp
  - subscriptionStatus: string
  - subscriptionTier: string

/projects/{projectId}
  - name: string
  - ownerUserID: string
  - artistName: string
  - status: string
  - workflowStage: string
  - createdAt: timestamp
  - updatedAt: timestamp
  - shareCode: string (6 chars - for entire project)
  - isArchived: boolean

  /reviewers/{reviewerId}
    - userId: string
    - email: string
    - displayName: string
    - role: string
    - isKeyApprover: boolean
    - inviteStatus: string
    - createdAt: timestamp

  /songs/{songId}
    - name: string
    - artist: string
    - status: string
    - createdAt: timestamp
    - sortOrder: number
    - isArchived: boolean

    /mixes/{mixId}
      - name: string
      - versionNumber: number
      - cloudURL: string  // CRITICAL: Download URL from Firebase Storage
      - duration: number
      - approvalStatus: string
      - createdAt: timestamp
      - isUploaded: boolean

      /comments/{commentId}
        - timestamp: number
        - text: string
        - authorID: string
        - authorName: string
        - status: string
        - createdAt: timestamp

      /approvals/{approvalId}
        - status: string
        - note: string
        - createdAt: timestamp
        - updatedAt: timestamp

/guest_access/{guestCodeId}  // NEW COLLECTION
  - code: string (indexed)
  - projectId: string
  - songId: string
  - mixId: string
  - canComment: boolean
  - createdBy: string
  - createdAt: timestamp
  - expiresAt: timestamp
  - isActive: boolean
  - accessCount: number
```

### Firebase Storage Structure

```
/projects/{projectId}/songs/{songId}/mixes/{mixId}/
  - audio.m4a (or .mp3, .wav)
  - waveform.json (optional - pre-computed waveform data)
```

**Important:** The iOS app already uploads audio to this structure. The `cloudURL` field in the Mix document contains the download URL.

---

## Authentication & Guest Codes

### Guest Code System

**Code Generation (iOS App):**
1. Producer selects "Share Mix with Guest" in iOS app
2. App generates 8-character alphanumeric code (e.g., "AB12-CD34")
3. Creates `guest_access` document in Firestore
4. Returns shareable link: `https://sessionproof.app/g/AB12-CD34`

**Code Validation (Web App):**
1. Guest visits URL or enters code manually
2. Web app queries Firestore: `guest_access` where `code == AB12-CD34`
3. Validates:
   - Code exists
   - `isActive == true`
   - Not expired (`expiresAt > now()` if set)
4. If valid, fetches mix data and displays player

**Security Rules (Firestore):**
```javascript
// Guest access collection - read by code
match /guest_access/{guestId} {
  allow read: if request.auth != null ||
    (resource.data.code == request.query.code && resource.data.isActive == true);
  allow create, update: if request.auth != null &&
    request.auth.uid == request.resource.data.createdBy;
}

// Projects - guests can read if they have valid code
match /projects/{projectId} {
  allow read: if request.auth != null ||
    hasValidGuestCode(projectId);
}

// Songs - guests can read if they have valid code
match /projects/{projectId}/songs/{songId} {
  allow read: if request.auth != null ||
    hasValidGuestCodeForSong(projectId, songId);
}

// Mixes - guests can read if they have valid code
match /projects/{projectId}/songs/{songId}/mixes/{mixId} {
  allow read: if request.auth != null ||
    hasValidGuestCodeForMix(projectId, songId, mixId);

  // Comments - guests can create if they have valid code with comment permission
  match /comments/{commentId} {
    allow read: if request.auth != null ||
      hasValidGuestCodeForMix(projectId, songId, mixId);
    allow create: if hasValidGuestCodeWithCommentPermission(projectId, songId, mixId);
  }

  // Approvals - read only for guests
  match /approvals/{approvalId} {
    allow read: if request.auth != null ||
      hasValidGuestCodeForMix(projectId, songId, mixId);
  }
}

// Helper functions
function hasValidGuestCode(projectId) {
  let guestCode = request.auth.token.guestCode;  // Set via custom claim
  let guestAccess = get(/databases/$(database)/documents/guest_access/$(guestCode));
  return guestAccess.data.isActive == true &&
         guestAccess.data.projectId == projectId &&
         (guestAccess.data.expiresAt == null || guestAccess.data.expiresAt > request.time);
}

function hasValidGuestCodeForMix(projectId, songId, mixId) {
  let guestCode = request.auth.token.guestCode;
  let guestAccess = get(/databases/$(database)/documents/guest_access/$(guestCode));
  return guestAccess.data.isActive == true &&
         guestAccess.data.projectId == projectId &&
         guestAccess.data.songId == songId &&
         guestAccess.data.mixId == mixId;
}

function hasValidGuestCodeWithCommentPermission(projectId, songId, mixId) {
  let guestCode = request.auth.token.guestCode;
  let guestAccess = get(/databases/$(database)/documents/guest_access/$(guestCode));
  return hasValidGuestCodeForMix(projectId, songId, mixId) &&
         guestAccess.data.canComment == true;
}
```

---

## Core Features

### 1. Guest Login Flow

**URL Structure:**
- Entry: `https://sessionproof.app/g/{CODE}`
- Redirects to: `https://sessionproof.app/mix/{CODE}`

**UI Flow:**
```
1. Landing page with code input
   - "Enter your guest code"
   - Input: [____-____]
   - Button: "Access Mix"

2. Optional: Guest name prompt
   - "What's your name? (optional)"
   - Helps identify comments later

3. Validation & redirect
   - Show loading spinner
   - Validate code in Firestore
   - If valid: redirect to player
   - If invalid: show error "Invalid or expired code"
```

### 2. Audio Player with Waveform

**Requirements:**
- Display waveform visualization (use WaveSurfer.js)
- Standard playback controls (play/pause, seek, volume)
- Current time / total duration display
- Click waveform to seek
- Click waveform to add comment marker

**Implementation Notes:**
- Load audio from `mix.cloudURL` (Firebase Storage URL)
- Generate waveform on-the-fly or use cached `waveformCache` if available
- Show comment markers on waveform timeline

### 3. Comments System

**Display Comments:**
- List all comments sorted by timestamp
- Each comment shows:
  - Timestamp (formatted as MM:SS)
  - Author name
  - Comment text
  - Status badge (Open/Resolved)
  - Created date

**Create Comment:**
- Click waveform at desired position
- Modal/sheet appears:
  - Timestamp: [auto-filled]
  - Your name: [from guest name or "Guest"]
  - Comment: [textarea]
  - Button: "Submit"
- On submit:
  - Create comment in Firestore
  - Show success message
  - Update comment list

**Comment Permissions:**
- Guest can only create comments (not edit/delete)
- Guest can see all comments (if `canViewOtherComments == true`)

### 4. Approval Status Display

**Read-only for guests:**
- Show overall approval status of mix
- Display list of approvals:
  - Reviewer name
  - Status (Approved / Changes Requested / Pending)
  - Date
  - Note (if any)

**UI:**
- Status badge at top: "✓ Approved" / "⏳ In Review" / "⚠️ Changes Requested"
- Expandable section: "Approvals (3/5)"
  - List each reviewer's approval

---

## Technical Stack

### Recommended Technologies

**Frontend:**
- **React** (or Next.js for SSR/SSG)
- **TypeScript** (for type safety)
- **Tailwind CSS** (for styling)
- **WaveSurfer.js** (for waveform visualization)
  - Docs: https://wavesurfer-js.org/

**Backend/Services:**
- **Firebase JS SDK** (v9+)
  - Authentication (anonymous or custom token)
  - Firestore (database)
  - Storage (for audio downloads)
- **Firebase Hosting** (for deployment)

**Optional Enhancements:**
- **Zustand** or **Redux** (state management)
- **React Query** (for Firebase data fetching)
- **Framer Motion** (animations)

### Firebase Configuration

You'll need to initialize Firebase in your web app:

```typescript
import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getStorage } from 'firebase/storage';
import { getAuth } from 'firebase/auth';

// Get these values from your iOS app's GoogleService-Info.plist
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_AUTH_DOMAIN",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_STORAGE_BUCKET",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const storage = getStorage(app);
const auth = getAuth(app);

export { db, storage, auth };
```

**IMPORTANT:** Your iOS app already has these values in `GoogleService-Info.plist`. You'll need to extract them and use the same Firebase project.

---

## Security Considerations

### 1. Guest Access Limitations
- Guests have no access to user accounts
- Guests cannot see other projects/mixes
- Guests cannot modify approval status
- Guests cannot delete comments (even their own)

### 2. Code Expiration
- Producers can set expiration dates on guest codes
- Expired codes return "Access Denied" error
- Producers can manually deactivate codes

### 3. Rate Limiting
- Implement client-side rate limiting for comment creation
- Firestore Security Rules should prevent spam

### 4. Audio Access
- Firebase Storage URLs are publicly accessible (by design)
- This is acceptable for guest access use case
- If stricter control needed, use Firebase Storage Security Rules

### 5. CORS & Firebase Storage
- Ensure Firebase Storage has CORS configured for web access
- Set in Firebase Console → Storage → Rules

---

## Implementation Phases

### Phase 1: MVP (Minimum Viable Product)
**Goal:** Basic guest access with audio playback

**Features:**
- [ ] Guest code validation
- [ ] Audio player with basic controls
- [ ] Waveform visualization (basic)
- [ ] View existing comments
- [ ] Create text comments
- [ ] View approval status

**Deliverables:**
- Single-page web app
- Works on desktop and mobile browsers
- Deployed to Firebase Hosting

### Phase 2: Enhanced Experience
**Goal:** Improve UX and add features

**Features:**
- [ ] Improved waveform (zoom, custom colors)
- [ ] Comment threading/replies
- [ ] Real-time updates (Firebase listeners)
- [ ] Guest name persistence (localStorage)
- [ ] Share functionality (copy link)
- [ ] Download audio (if permitted)

### Phase 3: Advanced Features
**Goal:** Match iOS app feature parity

**Features:**
- [ ] Voice note comments (record in browser)
- [ ] Comment status management (mark resolved)
- [ ] Multiple mix versions (show version history)
- [ ] Notifications when new comments added
- [ ] Analytics for producers (who accessed, when)

---

## Example Code Snippets

### Validating Guest Code

```typescript
import { collection, query, where, getDocs } from 'firebase/firestore';
import { db } from './firebase';

async function validateGuestCode(code: string): Promise<GuestAccess | null> {
  const guestAccessRef = collection(db, 'guest_access');
  const q = query(guestAccessRef, where('code', '==', code));
  const snapshot = await getDocs(q);

  if (snapshot.empty) {
    return null;
  }

  const guestAccess = snapshot.docs[0].data() as GuestAccess;

  // Check if active
  if (!guestAccess.isActive) {
    throw new Error('This guest code has been deactivated');
  }

  // Check if expired
  if (guestAccess.expiresAt && guestAccess.expiresAt.toDate() < new Date()) {
    throw new Error('This guest code has expired');
  }

  return guestAccess;
}
```

### Fetching Mix Data

```typescript
import { doc, getDoc } from 'firebase/firestore';
import { db } from './firebase';

async function loadMix(projectId: string, songId: string, mixId: string) {
  // Load mix document
  const mixRef = doc(db, `projects/${projectId}/songs/${songId}/mixes/${mixId}`);
  const mixSnap = await getDoc(mixRef);

  if (!mixSnap.exists()) {
    throw new Error('Mix not found');
  }

  const mix = { id: mixSnap.id, ...mixSnap.data() } as Mix;

  // Load song and project for context
  const songRef = doc(db, `projects/${projectId}/songs/${songId}`);
  const songSnap = await getDoc(songRef);
  const song = { id: songSnap.id, ...songSnap.data() } as Song;

  const projectRef = doc(db, `projects/${projectId}`);
  const projectSnap = await getDoc(projectRef);
  const project = { id: projectSnap.id, ...projectSnap.data() } as Project;

  return { mix, song, project };
}
```

### Creating a Comment

```typescript
import { collection, addDoc } from 'firebase/firestore';
import { db } from './firebase';

async function createComment(
  projectId: string,
  songId: string,
  mixId: string,
  timestamp: number,
  text: string,
  authorName: string
) {
  const commentsRef = collection(
    db,
    `projects/${projectId}/songs/${songId}/mixes/${mixId}/comments`
  );

  await addDoc(commentsRef, {
    timestamp,
    text,
    authorID: 'guest',  // Special ID for guests
    authorName,
    status: 'Open',
    createdAt: new Date(),
  });
}
```

### WaveSurfer.js Integration

```typescript
import WaveSurfer from 'wavesurfer.js';

function initializeWaveform(audioUrl: string, containerRef: HTMLElement) {
  const wavesurfer = WaveSurfer.create({
    container: containerRef,
    waveColor: '#4F46E5',
    progressColor: '#818CF8',
    cursorColor: '#C7D2FE',
    height: 128,
    normalize: true,
    backend: 'WebAudio',
  });

  wavesurfer.load(audioUrl);

  // Add comment markers
  wavesurfer.on('click', (progress) => {
    const timestamp = progress * wavesurfer.getDuration();
    openCommentDialog(timestamp);
  });

  return wavesurfer;
}
```

---

## Next Steps

### 1. Extract Firebase Configuration
From your iOS app's `GoogleService-Info.plist`, get:
- API_KEY
- PROJECT_ID
- STORAGE_BUCKET
- etc.

### 2. Set Up Firestore Security Rules
Add the guest access rules shown in the "Authentication & Guest Codes" section.

### 3. Create Guest Access Collection
You may want to add this to your iOS app first:
- Add "Share with Guest" button to mix detail view
- Generate guest code
- Create `guest_access` document in Firestore
- Display shareable link

### 4. Start Web Development
Use Claude to build the web app with this spec as context!

**Sample prompt for Claude:**
```
I need to build a web app based on this specification. Let's start with:
1. Setting up a Next.js project with TypeScript and Tailwind
2. Initializing Firebase (I'll provide my config)
3. Creating the guest code validation flow
4. Building the audio player with WaveSurfer.js

I've attached the full specification document. Let's begin!
```

---

## Appendix: iOS App Code to Share

When building the web app, you may want to reference these iOS files for understanding the data flow:

1. **Models/** - All 5 model files (already included above)
2. **FirestoreService.swift** - Shows how iOS app interacts with Firestore
3. **CloudStorageService.swift** - Shows how audio is uploaded to Firebase Storage
4. **MixInspectorView.swift** - Shows how comments/approvals are displayed in iOS

These will help Claude understand the complete system architecture.

---

**End of Specification**

Questions? Share this document with Claude in claude.ai or Claude Code when building the web app!
