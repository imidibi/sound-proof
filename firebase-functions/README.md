# Approvl Firebase Cloud Functions

This directory contains Firebase Cloud Functions that handle push notifications for the Approvl app.

## Functions

### 1. `onMixCreated`
Triggers when a new mix is uploaded to a project.
- **Notifies**: All accepted approvers (excluding the producer)
- **Message**: "New Mix: [Mix Name]" - "[Song Name] - Ready for your review in [Project Name]"

### 2. `onMixUpdated`
Triggers when a mix is updated with a new version.
- **Notifies**: All accepted approvers (excluding the producer)
- **Message**: "Mix Updated: [Mix Name]" - "[Song Name] - New version available in [Project Name]"
- **Note**: Only triggers if version number changes (not metadata-only updates)

### 3. `onCommentCreated`
Triggers when an approver comments on a mix.
- **Notifies**: The project producer
- **Message**: "New Comment on [Mix Name]" - "[Author]: [Comment text...]"
- **Note**: Doesn't notify if producer comments on their own mix

### 4. `onApprovalUpdated`
Triggers when an approver changes their approval status.
- **Notifies**: The project producer
- **Messages**:
  - Approved: "✅ [Mix Name] Approved" - "[User] approved [Song Name]"
  - Needs Revision: "🔄 Changes Requested: [Mix Name]" - "[User] requested changes"
- **Note**: Doesn't notify if producer changes their own approval

## Prerequisites

1. **Node.js 18+**: Install from [nodejs.org](https://nodejs.org/)
2. **Firebase CLI**: Install globally
   ```bash
   npm install -g firebase-tools
   ```

## Setup

1. **Navigate to this directory:**
   ```bash
   cd firebase-functions
   ```

2. **Install dependencies:**
   ```bash
   cd functions
   npm install
   ```

3. **Login to Firebase:**
   ```bash
   firebase login
   ```

4. **Select your Firebase project:**
   ```bash
   firebase use approvl
   ```
   (Replace 'approvl' with your actual Firebase project ID)

## Deployment

### Deploy all functions:
```bash
firebase deploy --only functions
```

### Deploy a specific function:
```bash
firebase deploy --only functions:onMixCreated
firebase deploy --only functions:onMixUpdated
firebase deploy --only functions:onCommentCreated
firebase deploy --only functions:onApprovalUpdated
```

## Testing

### Local Testing (Emulator):
```bash
npm run serve
```
This starts the Firebase emulators for local testing.

### View Logs:
```bash
npm run logs
```

Or in Firebase Console → Functions → Logs

## How It Works

1. **Firestore Triggers**: Functions automatically trigger when documents are created/updated in Firestore
2. **FCM Token Lookup**: Functions retrieve FCM tokens from user documents
3. **Notification Sending**: Uses Firebase Cloud Messaging to send push notifications
4. **Deep Link Data**: Includes project/song/mix IDs in notification data for navigation

## Data Structure Expected

### User Document (`users/{userId}`):
```javascript
{
  fcmToken: "string",           // Required for notifications
  fcmTokenUpdatedAt: Timestamp,
  email: "string",
  displayName: "string",
  // ... other fields
}
```

### Reviewer Document (`projects/{projectId}/reviewers/{reviewerId}`):
```javascript
{
  userId: "string",             // Required to look up FCM token
  inviteStatus: "Accepted",     // Only "Accepted" reviewers get notified
  displayName: "string",
  // ... other fields
}
```

## Troubleshooting

### No notifications received:
1. Check that FCM tokens are saved in Firestore (`users` collection)
2. Verify functions deployed successfully: `firebase functions:list`
3. Check function logs: `npm run logs` or Firebase Console
4. Ensure app has Push Notifications capability enabled
5. Verify notification permissions granted on device

### Function errors:
1. Check logs in Firebase Console → Functions → Logs
2. Verify Firestore security rules allow function access
3. Ensure all required user/reviewer data exists in Firestore

## Cost Considerations

- Functions are billed based on:
  - Number of invocations
  - Execution time
  - Outbound network
- FCM messages are free (no cost for sending notifications)
- Firestore reads are billed per document read

The free tier includes:
- 2M function invocations/month
- 400K GB-seconds compute time
- 200K CPU-seconds

For most usage patterns, these functions should stay within free tier limits.

## Future Enhancements

Potential additions:
- [ ] Batch notifications for multiple events
- [ ] User notification preferences (mute specific projects)
- [ ] Digest notifications (daily/weekly summaries)
- [ ] @mentions in comments
- [ ] Due date reminders
