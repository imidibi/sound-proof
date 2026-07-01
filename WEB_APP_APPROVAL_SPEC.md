# Web App Approval System Specification

**Version:** 1.0
**Date:** June 2026
**Purpose:** Technical specification for implementing approver approval functionality in the web guest access app

---

## Table of Contents
1. [Overview](#overview)
2. [Key Concepts](#key-concepts)
3. [Data Model](#data-model)
4. [User Permissions](#user-permissions)
5. [API Operations](#api-operations)
6. [UI/UX Requirements](#uiux-requirements)
7. [Implementation Guide](#implementation-guide)

---

## Overview

The Session Proof app has a **two-tier approval system**:

1. **Individual Approver Opinions** - Each approver/reviewer can personally approve or request changes to a mix. This is their individual opinion.
2. **Final Mix Approval** - Only the **project owner** (producer) or **key approver** can set the final approval status of the mix, which determines if it's officially approved for the song.

### Important Distinction:
- **Approver's personal approval** = Their individual opinion (stored in `approvals` subcollection)
- **Mix's overall approval status** = The official status set by producer/key approver (stored on the `mix` document itself)

**For the web app**: Regular approvers (including guests with approval permissions) can **only** set their personal approval opinion. They **cannot** change the mix's final approval status.

---

## Key Concepts

### Roles & Permissions

**Producer/Project Owner:**
- Can do everything
- Can set final mix approval status
- Can see all approvals from reviewers

**Key Approver:**
- Special reviewer designated by the producer
- **Only ONE per project**
- Can set final mix approval status (like producer)
- Can see all approvals
- Identified by: `reviewer.isKeyApprover == true`

**Regular Approver/Reviewer:**
- Can view the mix
- Can leave comments
- **Can set their personal approval opinion**
- Cannot change the mix's final status
- This is what web app approvers will be

**Guest (Web App):**
- May or may not have approval permission (set in `guest_access` document)
- If `guestCanComment == true`, they can comment
- If guest has approval permission, they function like a regular approver

---

## Data Model

### Approval Document Structure

**Location in Firestore:**
```
/projects/{projectId}/songs/{songId}/mixes/{mixId}/approvals/{reviewerUserId}
```

**Document ID:** The `reviewerUserId` (Firebase Auth UID of the reviewer)

**Fields:**
```typescript
interface Approval {
  reviewerUserId: string;      // Firebase Auth UID of the reviewer
  status: 'In Review' | 'Approved' | 'Changes Requested';
  createdAt: Timestamp;        // When approval was first created
  updatedAt: Timestamp;        // When approval was last modified
  note?: string;               // Optional note (currently not implemented in iOS)
}
```

### Approval Status Values

The `status` field can have exactly **three values**:

1. **"In Review"** (default)
   - Approver is still reviewing
   - UI: 👀 In Review

2. **"Approved"**
   - Approver approves this mix
   - UI: ✅ Approved

3. **"Changes Requested"**
   - Approver wants changes
   - UI: ⚠️ Changes Requested

### Mix Document - Approval Status Field

**IMPORTANT:** The `mix` document itself has an `approvalStatus` field:

```typescript
interface Mix {
  // ... other fields
  approvalStatus: 'Draft' | 'Shared' | 'In Review' | 'Approved' | 'Superseded';
  // ... other fields
}
```

**Web app guests CANNOT modify this field.** This is controlled only by:
- Project owner (producer)
- Key approver

The individual approval documents in the `approvals` subcollection are **separate** from this field.

---

## User Permissions

### What Web App Approvers CAN Do:
✅ View the mix
✅ Play the audio
✅ See all comments
✅ Create comments (if `guestCanComment == true`)
✅ **Create/update their personal approval** (if they have permission)
✅ See other approvers' approval opinions
✅ See the mix's final approval status (read-only)

### What Web App Approvers CANNOT Do:
❌ Change the mix's `approvalStatus` field
❌ Delete or modify other approvers' approvals
❌ Delete their own approval (only create/update)
❌ See the list of reviewers (emails/names) - this is hidden from guests

---

## API Operations

### 1. Check If Current User Has Approval Permission

**Prerequisites:**
- User must be authenticated (either as a real Firebase user or as an anonymous guest with custom claims)
- If guest, must have `guestCanComment: true` in their guest code

**How to check:**
```typescript
// For real authenticated users (reviewers)
const isReviewer = await checkIfUserIsReviewer(projectId, currentUserId);

// For guests
const guestCanApprove = auth.currentUser?.token?.guestCanComment === true;

const canApprove = isReviewer || guestCanApprove;
```

### 2. Get Current User's Approval

**Firestore Path:**
```
/projects/{projectId}/songs/{songId}/mixes/{mixId}/approvals/{currentUserId}
```

**Code:**
```typescript
import { doc, getDoc } from 'firebase/firestore';

async function getMyApproval(
  projectId: string,
  songId: string,
  mixId: string,
  currentUserId: string
): Promise<Approval | null> {
  const approvalRef = doc(
    db,
    'projects', projectId,
    'songs', songId,
    'mixes', mixId,
    'approvals', currentUserId
  );

  const approvalSnap = await getDoc(approvalRef);

  if (approvalSnap.exists()) {
    return {
      reviewerUserId: approvalSnap.id,
      ...approvalSnap.data()
    } as Approval;
  }

  return null;
}
```

### 3. Create or Update Approval

**Method:** Use Firestore `setData()` with `merge: true`

**Code:**
```typescript
import { doc, setDoc, Timestamp } from 'firebase/firestore';

async function setMyApproval(
  projectId: string,
  songId: string,
  mixId: string,
  currentUserId: string,
  status: 'In Review' | 'Approved' | 'Changes Requested'
): Promise<void> {
  const approvalRef = doc(
    db,
    'projects', projectId,
    'songs', songId,
    'mixes', mixId,
    'approvals', currentUserId
  );

  const now = Timestamp.now();

  // Check if approval exists to determine if this is create or update
  const existingApproval = await getDoc(approvalRef);

  const data = {
    reviewerUserId: currentUserId,
    status: status,
    updatedAt: now,
    // Only set createdAt if creating new approval
    ...(existingApproval.exists() ? {} : { createdAt: now })
  };

  await setDoc(approvalRef, data, { merge: true });
}
```

### 4. Get All Approvals for a Mix

**Code:**
```typescript
import { collection, getDocs } from 'firebase/firestore';

async function getAllApprovals(
  projectId: string,
  songId: string,
  mixId: string
): Promise<Approval[]> {
  const approvalsRef = collection(
    db,
    'projects', projectId,
    'songs', songId,
    'mixes', mixId,
    'approvals'
  );

  const snapshot = await getDocs(approvalsRef);

  return snapshot.docs.map(doc => ({
    reviewerUserId: doc.id,
    ...doc.data()
  } as Approval));
}
```

### 5. Real-time Listener for Approvals

**Code:**
```typescript
import { collection, onSnapshot } from 'firebase/firestore';

function listenToApprovals(
  projectId: string,
  songId: string,
  mixId: string,
  callback: (approvals: Approval[]) => void
): () => void {
  const approvalsRef = collection(
    db,
    'projects', projectId,
    'songs', songId,
    'mixes', mixId,
    'approvals'
  );

  const unsubscribe = onSnapshot(approvalsRef, (snapshot) => {
    const approvals = snapshot.docs.map(doc => ({
      reviewerUserId: doc.id,
      ...doc.data()
    } as Approval));

    callback(approvals);
  });

  return unsubscribe;
}
```

---

## UI/UX Requirements

### Approval UI Component

**Location:** Display in the mix player interface, likely in a sidebar or below the waveform

**Component Structure:**

```
┌─────────────────────────────────────┐
│ MY APPROVAL                         │
├─────────────────────────────────────┤
│ Select your approval status:        │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ 👀 In Review               ▼    │ │ <- Dropdown/Menu
│ └─────────────────────────────────┘ │
│                                     │
│ Options:                            │
│ • 👀 In Review                      │
│ • ✅ Approved                       │
│ • ⚠️ Changes Requested              │
└─────────────────────────────────────┘
```

**UI States:**

1. **No Permission to Approve**
   - Don't show the approval UI at all
   - Only show view-only approval status

2. **Has Permission, No Approval Set**
   - Show dropdown with "In Review" selected
   - Label: "Set Your Approval"

3. **Has Permission, Approval Already Set**
   - Show dropdown with current status selected
   - Label: "My Approval"
   - Allow changing the status

4. **Updating/Saving**
   - Show loading indicator
   - Disable the dropdown during save

### Approval Display (All Approvals)

Show a **read-only list** of all approvals for the mix:

```
┌─────────────────────────────────────┐
│ APPROVALS (3/5)                     │
├─────────────────────────────────────┤
│ ✅ You                              │
│    Approved                         │
│                                     │
│ ⚠️ Other Reviewer                   │
│    Changes Requested                │
│                                     │
│ 👀 Another Reviewer                 │
│    In Review                        │
└─────────────────────────────────────┘
```

**Notes:**
- Show current user's approval at the top
- List other approvals below
- **Do NOT show reviewer names/emails** for guest users (privacy)
- For guests, just show "Reviewer #1", "Reviewer #2", etc.
- Only show the count: "3/5" = 3 approvals received out of 5 total reviewers

### Mix Overall Status Display

Show the **mix's final approval status** (read-only for web guests):

```
┌─────────────────────────────────────┐
│ MIX STATUS                          │
├─────────────────────────────────────┤
│ Status: ✅ Approved                 │
│                                     │
│ (Set by project owner or key        │
│  approver)                          │
└─────────────────────────────────────┘
```

This is the `mix.approvalStatus` field - **web guests cannot change this**.

---

## Implementation Guide

### Step 1: Check User Permission

When the mix player loads:

```typescript
// 1. Determine if user can approve
const currentUserId = auth.currentUser?.uid;
const guestCanApprove = auth.currentUser?.token?.guestCanComment === true;

if (!currentUserId) {
  // Not authenticated - no approval UI
  return;
}

// 2. Fetch current approval
const myApproval = await getMyApproval(projectId, songId, mixId, currentUserId);

// 3. Show UI if user can approve
if (guestCanApprove || isRealReviewer) {
  showApprovalUI(myApproval?.status || 'In Review');
}
```

### Step 2: Handle Approval Change

```typescript
async function handleApprovalChange(newStatus: ApprovalStatus) {
  try {
    setLoading(true);

    await setMyApproval(
      projectId,
      songId,
      mixId,
      currentUserId,
      newStatus
    );

    showSuccessMessage(`Approval updated to: ${newStatus}`);
  } catch (error) {
    console.error('Error updating approval:', error);
    showErrorMessage('Failed to update approval. Please try again.');
  } finally {
    setLoading(false);
  }
}
```

### Step 3: Display All Approvals

```typescript
// Set up real-time listener
useEffect(() => {
  const unsubscribe = listenToApprovals(
    projectId,
    songId,
    mixId,
    (approvals) => {
      setAllApprovals(approvals);
    }
  );

  return () => unsubscribe();
}, [projectId, songId, mixId]);

// Render
const renderApprovals = () => {
  const myApprovalData = allApprovals.find(a => a.reviewerUserId === currentUserId);
  const otherApprovals = allApprovals.filter(a => a.reviewerUserId !== currentUserId);

  return (
    <div>
      <h3>Approvals ({allApprovals.length}/{totalReviewers})</h3>

      {myApprovalData && (
        <ApprovalItem
          label="You"
          status={myApprovalData.status}
          isMe={true}
        />
      )}

      {otherApprovals.map((approval, index) => (
        <ApprovalItem
          key={approval.reviewerUserId}
          label={`Reviewer #${index + 1}`}  // Don't expose names to guests
          status={approval.status}
          isMe={false}
        />
      ))}
    </div>
  );
};
```

### Step 4: Error Handling

**Common Errors:**

1. **Permission Denied**
   - User doesn't have `guestCanComment` permission
   - Solution: Don't show approval UI

2. **Network Error**
   - Firestore connection failed
   - Solution: Show retry button

3. **Document Not Found**
   - Mix/project doesn't exist
   - Solution: Show error message

---

## Firestore Security Rules

The corrected rules already support this functionality:

```javascript
match /mixes/{mixId} {
  // Guests can read
  allow read: if isGuestForMix(projectId, songId, mixId);

  match /approvals/{approvalId} {
    // Guests can read all approvals
    allow read: if isGuestForMix(projectId, songId, mixId);

    // Guests can create/update ONLY if they have comment permission
    // AND the approval document ID matches their user ID
    allow create, update: if isGuestForMix(projectId, songId, mixId) &&
                             guestCanComment() &&
                             approvalId == request.auth.uid;

    // Guests CANNOT delete approvals
    allow delete: if false;
  }
}
```

**Key Points:**
- Approval document ID **must match** the user's auth UID
- Guests can only modify their own approval (document ID = their user ID)
- Guests cannot delete approvals (even their own)
- Reading approvals is allowed for all guests

---

## Testing Checklist

### Functional Testing

- [ ] Guest with `guestCanComment: true` can see approval UI
- [ ] Guest with `guestCanComment: false` cannot see approval UI
- [ ] Guest can create new approval (initially "In Review")
- [ ] Guest can update their approval to "Approved"
- [ ] Guest can update their approval to "Changes Requested"
- [ ] Guest can change back to "In Review"
- [ ] Changes persist after page refresh
- [ ] Real-time updates work when another user changes their approval
- [ ] Guest can see other approvals (anonymized)
- [ ] Guest cannot see reviewer names/emails
- [ ] Guest cannot change mix's overall `approvalStatus` field
- [ ] Approval count is accurate

### Error Handling

- [ ] Error message shown if save fails
- [ ] Retry mechanism works
- [ ] Loading state displays correctly
- [ ] Network errors handled gracefully
- [ ] Permission denied handled gracefully

### UI/UX

- [ ] Approval UI is intuitive
- [ ] Current status is clearly displayed
- [ ] Loading indicators work
- [ ] Success confirmation shown
- [ ] Mobile-friendly layout
- [ ] Accessible (keyboard navigation, screen readers)

---

## Summary

**What to Implement:**

1. **Check permission** - Only show approval UI if guest has `guestCanComment: true`
2. **Fetch current approval** - Load user's existing approval from Firestore
3. **Display approval picker** - Show dropdown with 3 options: In Review, Approved, Changes Requested
4. **Save approval** - Use `setDoc()` with merge to create/update approval document
5. **Display all approvals** - Show read-only list of all approvals (anonymized for guests)
6. **Real-time updates** - Use Firestore listeners to update UI when approvals change

**What NOT to Implement:**

- ❌ Don't allow changing mix's `approvalStatus` field (that's for producers/key approvers only)
- ❌ Don't show reviewer names/emails to guests
- ❌ Don't allow deleting approvals

**Document to Modify:**
```
/projects/{projectId}/songs/{songId}/mixes/{mixId}/approvals/{currentUserId}
```

**Fields to Write:**
```typescript
{
  reviewerUserId: string,      // Current user's ID
  status: string,              // One of: "In Review", "Approved", "Changes Requested"
  createdAt: Timestamp,        // Set once on creation
  updatedAt: Timestamp         // Update on every change
}
```

---

**End of Specification**

Questions? This spec should provide everything needed to implement approver approval functionality in the web guest access app!
