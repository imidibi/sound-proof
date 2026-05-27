# Approvl - Multi-Device Test Plan

**Date Created:** 2026-05-26
**Version:** 1.0
**Features Under Test:** Notifications, Email Invitations, Project Archiving, Status Codes, Auto-Sync

---

## Test Environment Setup

### Required Devices
- **Mac (Producer):** testproducer@example.com
- **iPad 1 (Approver):** testartist2@example.com
- **iPad 2 (Approver):** testartist3@example.com

### Pre-Test Checklist
- [ ] All devices have the latest build installed
- [ ] All devices have internet connectivity
- [ ] All test accounts are logged in
- [ ] Push notifications are enabled on all devices
- [ ] Firebase Cloud Functions are deployed (onReviewerAdded)
- [ ] Clear all existing test projects before starting

---

## Test Suite 1: Reviewer Invitations & Push Notifications

### Test 1.1: New Project Invitation with Registered User
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, create a new project "Test Notifications"
2. Add testartist2@example.com as an approver
3. Verify on iPad 1:
   - [ ] Push notification received immediately: "🎵 New Project: Test Notifications"
   - [ ] Notification body: "testproducer invited you to review their project"
   - [ ] Project appears in list WITHOUT manual sync
   - [ ] Tap notification to verify app opens

**Expected Logs:**
- Mac: `✅ Reviewer added to project successfully`
- iPad 1: `📱 Received notification while app in foreground` OR `📱 User tapped notification`
- iPad 1: `📱 Notification type 'project_invitation' requires sync - triggering background sync`
- iPad 1: `🔄 Triggered background sync from notification: project_invitation`
- iPad 1: `✅ Background sync completed after notification: project_invitation`

**Pass Criteria:**
- Notification arrives within 5 seconds
- Project syncs automatically without manual intervention
- All log messages appear correctly

---

### Test 1.2: Project Invitation to Unregistered Email
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, create new project "Test Email Invite"
2. Add unregistered email: newuser@example.com
3. On iPad 1, sign out of testartist2
4. Sign in as newuser@example.com (new account)
5. Verify:
   - [ ] Project "Test Email Invite" appears after login
   - [ ] User can access project without re-invitation

**Expected Logs:**
- Mac: `✅ Reviewer added to project successfully`
- iPad 1 (after login): `📦 Found 1 projects where user is a reviewer`

**Pass Criteria:**
- Email-based invitation is backfilled to userId after registration
- No duplicate reviewer records created

---

## Test Suite 2: Approval Status & Notifications

### Test 2.1: Approve Mix - Producer Notification
**Devices:** iPad 1 (Approver) + Mac (Producer)

**Steps:**
1. On Mac, add a song and mix to "Test Notifications" project
2. On iPad 1, navigate to the mix
3. Set approval status to "Approved"
4. Verify on Mac:
   - [ ] Push notification received: "✅ {MixName} Approved"
   - [ ] Notification body: "testartist2 approved {SongName} in Test Notifications"
   - [ ] Mix status updates WITHOUT manual sync
   - [ ] Approval status shows in UI

**Expected Logs:**
- iPad 1: `✅ Created approval with status: Approved`
- Mac: `📱 Received notification while app in foreground`
- Mac: `📱 Notification type 'approval_status_changed' requires sync`
- Mac: `✅ Background sync completed after notification`

**Pass Criteria:**
- Producer receives notification immediately
- Status syncs automatically on producer's Mac
- Firebase Function logs show successful send

---

### Test 2.2: Request Changes - Producer Notification
**Devices:** iPad 1 (Approver) + Mac (Producer)

**Steps:**
1. On iPad 1, navigate to the same mix
2. Change approval status to "Changes Requested"
3. Verify on Mac:
   - [ ] Push notification received: "🔄 Changes Requested: {MixName}"
   - [ ] Notification body: "testartist2 requested changes to {SongName}"
   - [ ] Status updates automatically

**Pass Criteria:**
- Notification arrives within 5 seconds
- Status change syncs without manual intervention

---

### Test 2.3: Pending Status - No Notification
**Devices:** iPad 1 (Approver) + Mac (Producer)

**Steps:**
1. On iPad 1, change approval status back to "Pending"
2. Verify on Mac:
   - [ ] NO push notification received
   - [ ] Status still updates on next sync (periodic or manual)

**Pass Criteria:**
- No notification for "Pending" status (as designed)
- Status change persists correctly

---

## Test Suite 3: Project Archiving

### Test 3.1: Archive Project - Approver Access Removed
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, archive "Test Notifications" project
2. Verify on Mac:
   - [ ] Project moves to "Archived" section
   - [ ] Archive button changes to "Unarchive"
   - [ ] Project still accessible to producer
3. On iPad 1, trigger manual sync
4. Verify on iPad 1:
   - [ ] Project disappears from project list
   - [ ] Project is removed from local storage
   - [ ] No error messages shown

**Expected Logs:**
- Mac: `✅ Project archived successfully`
- iPad 1: `⏭️ Skipping archived project: Test Notifications`
- iPad 1: `🗑️ Removing locally cached project`

**Pass Criteria:**
- Archived projects hidden from approvers immediately on sync
- Producer retains access to archived projects
- Clean removal without errors

---

### Test 3.2: Unarchive Project - Approver Access Restored
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, unarchive "Test Notifications" project
2. Verify on Mac:
   - [ ] Project moves back to active projects list
   - [ ] Button changes to "Archive"
3. On iPad 1, trigger manual sync
4. Verify on iPad 1:
   - [ ] Project reappears in project list
   - [ ] All songs and mixes are accessible
   - [ ] Previous approval status preserved

**Expected Logs:**
- Mac: `✅ Project unarchived successfully`
- iPad 1: `✅ Found project: Test Notifications`
- iPad 1: `📦 Found 1 projects where user is a reviewer`

**Pass Criteria:**
- Unarchived projects visible to approvers again
- All project data intact

---

### Test 3.3: Archived Songs - Approver Cannot See
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, create project "Test Song Archive" with 3 songs
2. Archive 1 song
3. On iPad 1, verify:
   - [ ] Only 2 active songs visible
   - [ ] Archived song not accessible
4. On Mac, unarchive the song
5. On iPad 1, sync and verify:
   - [ ] All 3 songs now visible

**Expected Logs:**
- iPad 1: `⏭️ Skipping archived song`

**Pass Criteria:**
- Archived songs filtered correctly
- Unarchiving restores visibility

---

## Test Suite 4: Multi-Device Notifications

### Test 4.1: Multi-Device Token Management
**Devices:** Mac + iPad 1 + iPad 2 (all same producer account)

**Steps:**
1. Sign in as testproducer@example.com on all 3 devices
2. On iPad 1 (as approver testartist2), approve a mix
3. Verify on ALL producer devices:
   - [ ] Mac receives notification
   - [ ] iPad 1 (producer account) receives notification
   - [ ] iPad 2 (producer account) receives notification

**Expected Logs:**
- Firebase Function: `Attempting to send approval notification to producer (3 devices)`
- Firebase Function: `Sent approval notification: 3 succeeded, 0 failed`

**Pass Criteria:**
- All devices with same account receive notification
- No duplicate tokens stored
- Firebase Function logs show correct device count

---

### Test 4.2: Sign Out - Token Cleanup
**Devices:** Mac (Producer)

**Steps:**
1. On Mac, sign out of testproducer account
2. Check Firebase Console: users/{userId} document
3. Verify:
   - [ ] Mac's FCM token removed from fcmTokens array
   - [ ] Other device tokens remain in array

**Expected Logs:**
- Mac: `✅ Deleted FCM token for this device`

**Pass Criteria:**
- Only signing-out device's token is removed
- No impact on other devices

---

## Test Suite 5: Comment Notifications

### Test 5.1: New Comment - All Participants Notified
**Devices:** Mac (Producer) + iPad 1 (Approver) + iPad 2 (Approver)

**Steps:**
1. On Mac, create project "Test Comments" with 1 song and 1 mix
2. Add testartist2 and testartist3 as approvers
3. On iPad 1 (testartist2), add a comment at timestamp 1:30
4. Verify notifications:
   - [ ] Mac (producer) receives notification
   - [ ] iPad 2 (testartist3) receives notification
   - [ ] iPad 1 (testartist2 - commenter) does NOT receive notification

**Expected Logs:**
- Firebase Function: `Sent comment notification to 2 participants`

**Pass Criteria:**
- All participants except commenter receive notification
- Automatic sync triggers on receiving devices

---

## Test Suite 6: Auto-Sync on Notification

### Test 6.1: Notification Types That Trigger Sync
**Devices:** iPad 1 (Approver)

**Test each notification type triggers auto-sync:**

1. **project_invitation:**
   - [ ] New project appears without manual sync

2. **new_mix:**
   - [ ] New mix appears without manual sync

3. **mix_updated:**
   - [ ] Mix changes appear without manual sync

4. **approval_status_changed:**
   - [ ] Approval status updates without manual sync

5. **new_comment:**
   - [ ] New comment appears without manual sync

**Expected Logs (for each):**
- `📱 Notification type '{type}' requires sync - triggering background sync`
- `🔄 Triggered background sync from notification: {type}`
- `✅ Background sync completed after notification: {type}`

**Pass Criteria:**
- All 5 notification types trigger automatic sync
- No manual sync required for any update

---

## Test Suite 7: Edge Cases & Error Handling

### Test 7.1: Offline Notification Handling
**Devices:** iPad 1 (Approver)

**Steps:**
1. On iPad 1, enable Airplane Mode
2. On Mac, create new project and add testartist2
3. Wait 30 seconds
4. On iPad 1, disable Airplane Mode
5. Verify:
   - [ ] Notification arrives when connectivity restored
   - [ ] Auto-sync completes successfully
   - [ ] Project appears in list

**Pass Criteria:**
- Notifications queue while offline
- Sync completes when online

---

### Test 7.2: Rapid Status Changes
**Devices:** iPad 1 (Approver) + Mac (Producer)

**Steps:**
1. On iPad 1, rapidly change approval status:
   - Approved → Changes Requested → Approved → Changes Requested
2. Verify on Mac:
   - [ ] All notifications received in order
   - [ ] Final status is correct
   - [ ] No duplicate or missing notifications

**Pass Criteria:**
- All status changes captured
- No race conditions or lost updates

---

### Test 7.3: Large Project Sync Performance
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Steps:**
1. On Mac, create project with:
   - 20 songs
   - 3 mixes per song (60 total mixes)
   - 5 comments per mix (300 total comments)
2. Add testartist2 as approver
3. On iPad 1, verify:
   - [ ] Notification received
   - [ ] Auto-sync completes within 30 seconds
   - [ ] All data loads correctly
   - [ ] No crashes or memory issues

**Expected Logs:**
- `✅ Background sync completed after notification: project_invitation`

**Pass Criteria:**
- Large project syncs successfully
- Performance remains acceptable
- UI remains responsive

---

## Test Suite 8: Firestore Security Rules

### Test 8.1: Archived Project Access Control
**Devices:** iPad 1 (Approver)

**Steps:**
1. On Mac, create and archive project "Security Test"
2. Note the projectId from Firestore Console
3. On iPad 1, attempt to read project directly (via Firestore console or API):
   ```swift
   // This should be blocked by rules
   let doc = try await Firestore.firestore()
       .collection("projects")
       .document(projectId)
       .getDocument()
   ```
4. Verify:
   - [ ] Read succeeds (rules allow approvers to read)
   - [ ] Application-layer filtering hides it from UI

**Pass Criteria:**
- Security rules allow read access
- Application correctly filters archived projects

---

### Test 8.2: Approver Cannot Update Project Settings
**Devices:** iPad 1 (Approver)

**Steps:**
1. On iPad 1, attempt to modify project name via Firestore API
2. Verify:
   - [ ] Permission denied error
   - [ ] Project name unchanged

**Pass Criteria:**
- Only producer can update project metadata

---

## Test Suite 9: Periodic Background Sync

### Test 9.1: 5-Minute Periodic Sync
**Devices:** iPad 1 (Approver)

**Steps:**
1. On iPad 1, leave app open and idle
2. On Mac, add new song and mix to project
3. Wait 5 minutes
4. Verify on iPad 1:
   - [ ] New content appears automatically
   - [ ] Log shows periodic sync triggered

**Expected Logs (every 5 minutes):**
- `🔄 Starting periodic background sync...`
- `✅ Periodic project sync completed`

**Pass Criteria:**
- Periodic sync runs every 5 minutes
- Content updates without user action

---

## Test Suite 10: Regression Tests

### Test 10.1: Basic Workflow Still Works
**Devices:** Mac (Producer) + iPad 1 (Approver)

**Complete full workflow:**
1. [ ] Create project on Mac
2. [ ] Add approver via email
3. [ ] Add song and mix
4. [ ] Approver receives notification and sees project
5. [ ] Approver adds comment
6. [ ] Producer receives notification
7. [ ] Approver approves mix
8. [ ] Producer receives notification
9. [ ] Producer archives project
10. [ ] Approver loses access

**Pass Criteria:**
- All steps work without errors
- Notifications received at each step
- Data syncs correctly

---

## Firebase Console Verification

### After Each Test Session

**Check Firebase Console:**

1. **Firestore Database:**
   - [ ] No orphaned reviewer documents
   - [ ] fcmTokens arrays properly populated
   - [ ] Project status and isArchived flags correct
   - [ ] Approval records have correct status values

2. **Cloud Functions Logs:**
   - [ ] All functions executed successfully
   - [ ] No error traces in logs
   - [ ] Token counts match expected devices
   - [ ] Success/failure counts are accurate

3. **Authentication:**
   - [ ] All test users present
   - [ ] No duplicate accounts

---

## Known Issues & Workarounds

### Issue 1: Firebase Function Cold Start
**Symptom:** First notification of the day may be delayed 5-10 seconds
**Workaround:** Expected behavior - subsequent notifications are instant

### Issue 2: Multiple Reviewer Records
**Symptom:** Email-based and userId-based reviewer records may coexist temporarily
**Status:** Designed behavior - backfill system handles cleanup

---

## Test Results Log

| Test ID | Test Name | Date | Tester | Result | Notes |
|---------|-----------|------|--------|--------|-------|
| 1.1 | New Project Invitation | | | ☐ Pass ☐ Fail | |
| 1.2 | Email Invite to Unregistered | | | ☐ Pass ☐ Fail | |
| 2.1 | Approve Mix Notification | | | ☐ Pass ☐ Fail | |
| 2.2 | Request Changes Notification | | | ☐ Pass ☐ Fail | |
| 2.3 | Pending Status No Notification | | | ☐ Pass ☐ Fail | |
| 3.1 | Archive Project | | | ☐ Pass ☐ Fail | |
| 3.2 | Unarchive Project | | | ☐ Pass ☐ Fail | |
| 3.3 | Archived Songs Hidden | | | ☐ Pass ☐ Fail | |
| 4.1 | Multi-Device Tokens | | | ☐ Pass ☐ Fail | |
| 4.2 | Sign Out Token Cleanup | | | ☐ Pass ☐ Fail | |
| 5.1 | Comment Notifications | | | ☐ Pass ☐ Fail | |
| 6.1 | Auto-Sync All Types | | | ☐ Pass ☐ Fail | |
| 7.1 | Offline Notification | | | ☐ Pass ☐ Fail | |
| 7.2 | Rapid Status Changes | | | ☐ Pass ☐ Fail | |
| 7.3 | Large Project Performance | | | ☐ Pass ☐ Fail | |
| 8.1 | Archived Access Control | | | ☐ Pass ☐ Fail | |
| 8.2 | Approver Update Denied | | | ☐ Pass ☐ Fail | |
| 9.1 | Periodic Background Sync | | | ☐ Pass ☐ Fail | |
| 10.1 | Full Workflow Regression | | | ☐ Pass ☐ Fail | |

---

## Critical Path Tests (Quick Smoke Test)

**For rapid testing after builds, execute these high-priority tests:**

1. ✅ Test 1.1: New project invitation with notification
2. ✅ Test 2.1: Approve mix with producer notification
3. ✅ Test 3.1: Archive project removes approver access
4. ✅ Test 6.1: Auto-sync on notification receipt
5. ✅ Test 10.1: Full workflow regression

**Expected Duration:** 15-20 minutes

---

## Report Findings

**When bugs are found:**
1. Note test ID and step number
2. Capture device logs from all involved devices
3. Screenshot error states
4. Check Firebase Console for function logs
5. Document exact reproduction steps
6. Report via GitHub Issues with label `bug`

---

**End of Test Plan**
