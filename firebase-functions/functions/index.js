/**
 * Firebase Cloud Functions for Approvl
 *
 * Handles push notifications for:
 * - New mix uploads
 * - Mix updates
 * - Comments on mixes
 * - Approval status changes
 */

const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// Initialize Firebase Admin with explicit project ID
admin.initializeApp({
  projectId: "approvl",
});

const getFirestore = () => admin.firestore();
const getMessaging = () => admin.messaging();

/**
 * Send notification when a new mix is created
 * Notifies all accepted approvers that a new mix is ready for review
 */
exports.onMixCreated = onDocumentCreated(
  {
    document: "projects/{projectId}/songs/{songId}/mixes/{mixId}",
    database: "(default)",
  },
  async (event) => {
    const mixData = event.data.data();
    const {projectId, songId, mixId} = event.params;

    console.log(`New mix created: ${mixId} in project ${projectId}`);

    try {
      // Get project details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();
      const producerId = projectData.ownerUserId;

      // Get song details for context
      const songDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .get();

      const songName = songDoc.exists ? songDoc.data().name : "Unknown Song";

      // Get all accepted reviewers (approvers) for this project
      const reviewersSnapshot = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("reviewers")
        .where("inviteStatus", "==", "Accepted")
        .get();

      console.log(`Found ${reviewersSnapshot.size} accepted approvers`);

      // Collect FCM tokens for all approvers (exclude producer)
      const tokens = [];
      for (const reviewerDoc of reviewersSnapshot.docs) {
        const reviewer = reviewerDoc.data();

        // Skip the producer
        if (reviewer.userId === producerId) {
          continue;
        }

        // Get the user's FCM tokens (supports multiple devices)
        if (reviewer.userId) {
          const userDoc = await getFirestore()
            .collection("users")
            .doc(reviewer.userId)
            .get();

          if (userDoc.exists) {
            const userData = userDoc.data();
            // New format: array of tokens for multiple devices
            if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
              tokens.push(...userData.fcmTokens);
            }
            // Legacy format: single token (for backward compatibility)
            else if (userData.fcmToken) {
              tokens.push(userData.fcmToken);
            }
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No FCM tokens found for approvers");
        return;
      }

      // Send notification to all approvers
      const message = {
        notification: {
          title: `New Mix: ${mixData.name}`,
          body: `${songName} - Ready for your review in ${projectData.name}`,
        },
        data: {
          type: "new_mix",
          projectId: projectId,
          songId: songId,
          mixId: mixId,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: `New Mix: ${mixData.name}`,
                body: `${songName} - Ready for your review in ${projectData.name}`,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send to ${tokens.length} tokens`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent ${response.successCount} notifications`);

      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`Failed to send to token ${idx}:`, resp.error);
          }
        });
      }
    } catch (error) {
      console.error("Error sending new mix notification:", error);
    }
  }
);

/**
 * Send notification when a mix is updated
 * Notifies all accepted approvers that a mix has been updated
 */
exports.onMixUpdated = onDocumentUpdated(
  {
    document: "projects/{projectId}/songs/{songId}/mixes/{mixId}",
    database: "(default)",
  },
  async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();
    const {projectId, songId, mixId} = event.params;

    // Only notify if the mix file was actually updated (version number changed)
    if (oldData.versionNumber === newData.versionNumber) {
      console.log("Mix metadata updated but no new version - skipping notification");
      return;
    }

    console.log(`Mix updated: ${mixId} in project ${projectId}`);

    try {
      // Get project and song details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();
      const producerId = projectData.ownerUserId;

      const songDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .get();

      const songName = songDoc.exists ? songDoc.data().name : "Unknown Song";

      // Get all accepted reviewers
      const reviewersSnapshot = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("reviewers")
        .where("inviteStatus", "==", "Accepted")
        .get();

      // Collect FCM tokens
      const tokens = [];
      for (const reviewerDoc of reviewersSnapshot.docs) {
        const reviewer = reviewerDoc.data();

        if (reviewer.userId === producerId) {
          continue;
        }

        if (reviewer.userId) {
          const userDoc = await getFirestore()
            .collection("users")
            .doc(reviewer.userId)
            .get();

          if (userDoc.exists) {
            const userData = userDoc.data();
            // New format: array of tokens for multiple devices
            if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
              tokens.push(...userData.fcmTokens);
            }
            // Legacy format: single token (for backward compatibility)
            else if (userData.fcmToken) {
              tokens.push(userData.fcmToken);
            }
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No FCM tokens found");
        return;
      }

      const message = {
        notification: {
          title: `Mix Updated: ${newData.name}`,
          body: `${songName} - New version available in ${projectData.name}`,
        },
        data: {
          type: "mix_updated",
          projectId: projectId,
          songId: songId,
          mixId: mixId,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: `Mix Updated: ${newData.name}`,
                body: `${songName} - New version available in ${projectData.name}`,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send to ${tokens.length} tokens`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent ${response.successCount} notifications`);

      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`Failed to send to token ${idx}:`, resp.error);
          }
        });
      }
    } catch (error) {
      console.error("Error sending mix update notification:", error);
    }
  }
);

/**
 * Send notification when a comment is created
 * Notifies the producer when an approver comments
 */
exports.onCommentCreated = onDocumentCreated(
  {
    document: "projects/{projectId}/songs/{songId}/mixes/{mixId}/comments/{commentId}",
    database: "(default)",
  },
  async (event) => {
    const commentData = event.data.data();
    const {projectId, songId, mixId} = event.params;

    console.log(`New comment on mix ${mixId}`);

    try {
      // Get project details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();
      const producerId = projectData.ownerUserId;

      // Don't notify if the producer commented (they know they commented!)
      if (commentData.userId === producerId) {
        console.log("Producer commented - skipping notification");
        return;
      }

      // Get mix and song details
      const mixDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .collection("mixes")
        .doc(mixId)
        .get();

      const songDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .get();

      const mixName = mixDoc.exists ? mixDoc.data().name : "Mix";
      const songName = songDoc.exists ? songDoc.data().name : "Song";

      // Get producer's FCM tokens (all devices)
      const producerDoc = await getFirestore()
        .collection("users")
        .doc(producerId)
        .get();

      if (!producerDoc.exists) {
        console.log("Producer document not found");
        return;
      }

      const producerData = producerDoc.data();
      const tokens = [];

      // New format: array of tokens for multiple devices
      if (producerData.fcmTokens && Array.isArray(producerData.fcmTokens)) {
        tokens.push(...producerData.fcmTokens);
      }
      // Legacy format: single token (for backward compatibility)
      else if (producerData.fcmToken) {
        tokens.push(producerData.fcmToken);
      }

      if (tokens.length === 0) {
        console.log("Producer has no FCM tokens");
        return;
      }

      // Send notification to producer (all devices)
      const message = {
        notification: {
          title: `New Comment on ${mixName}`,
          body: `${commentData.authorName}: ${commentData.text.substring(0, 100)}${commentData.text.length > 100 ? "..." : ""}`,
        },
        data: {
          type: "comment",
          projectId: projectId,
          songId: songId,
          mixId: mixId,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: `New Comment on ${mixName}`,
                body: `${commentData.authorName}: ${commentData.text.substring(0, 100)}${commentData.text.length > 100 ? "..." : ""}`,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send comment notification to producer (${tokens.length} devices)`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent comment notification: ${response.successCount} succeeded, ${response.failureCount} failed`);
    } catch (error) {
      console.error("Error sending comment notification:", error);
    }
  }
);

/**
 * Send notification when a new approval is created
 * Notifies the producer when an approver sets their initial approval status
 */
exports.onApprovalCreated = onDocumentCreated(
  {
    document: "projects/{projectId}/songs/{songId}/mixes/{mixId}/approvals/{approvalId}",
    database: "(default)",
  },
  async (event) => {
    const approvalData = event.data.data();
    const {projectId, songId, mixId} = event.params;

    console.log(`New approval created with status ${approvalData.status} for mix ${mixId}`);

    try {
      // Get project details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();
      const producerId = projectData.ownerUserId;

      // Don't notify if the producer set their own approval
      if (approvalData.reviewerUserId === producerId) {
        console.log("Producer set their own approval - skipping notification");
        return;
      }

      // Only notify for Approved or Changes Requested status
      if (approvalData.status !== "Approved" && approvalData.status !== "Changes Requested") {
        console.log(`Status is ${approvalData.status} - skipping notification`);
        return;
      }

      // Get mix and song details
      const mixDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .collection("mixes")
        .doc(mixId)
        .get();

      const songDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .get();

      const mixName = mixDoc.exists ? mixDoc.data().name : "Mix";
      const songName = songDoc.exists ? songDoc.data().name : "Song";

      // Get reviewer name from the reviewerUserId
      let reviewerName = "An approver";
      if (approvalData.reviewerUserId) {
        const reviewerUserDoc = await getFirestore()
          .collection("users")
          .doc(approvalData.reviewerUserId)
          .get();

        if (reviewerUserDoc.exists) {
          reviewerName = reviewerUserDoc.data().displayName || reviewerName;
        }
      }

      // Get producer's FCM tokens (all devices)
      const producerDoc = await getFirestore()
        .collection("users")
        .doc(producerId)
        .get();

      if (!producerDoc.exists) {
        console.log("Producer document not found");
        return;
      }

      const producerData = producerDoc.data();
      const tokens = [];

      // New format: array of tokens for multiple devices
      if (producerData.fcmTokens && Array.isArray(producerData.fcmTokens)) {
        tokens.push(...producerData.fcmTokens);
      }
      // Legacy format: single token (for backward compatibility)
      else if (producerData.fcmToken) {
        tokens.push(producerData.fcmToken);
      }

      if (tokens.length === 0) {
        console.log("Producer has no FCM tokens");
        return;
      }

      // Create appropriate message based on status
      let title, body;
      if (approvalData.status === "Approved") {
        title = `✅ ${mixName} Approved`;
        body = `${reviewerName} approved ${songName} in ${projectData.name}`;
      } else if (approvalData.status === "Changes Requested") {
        title = `🔄 Changes Requested: ${mixName}`;
        body = `${reviewerName} requested changes to ${songName} in ${projectData.name}`;
      }

      // Send notification to producer (all devices)
      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "approval_status_changed",
          projectId: projectId,
          songId: songId,
          mixId: mixId,
          status: approvalData.status,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send approval notification to producer (${tokens.length} devices)`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent approval notification: ${response.successCount} succeeded, ${response.failureCount} failed`);

      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`Failed to send to token ${idx}:`, resp.error);
          }
        });
      }
    } catch (error) {
      console.error("Error sending approval notification:", error);
    }
  }
);

/**
 * Send notification when approval status changes
 * Notifies the producer when an approver approves or requests changes
 */
exports.onApprovalUpdated = onDocumentUpdated(
  {
    document: "projects/{projectId}/songs/{songId}/mixes/{mixId}/approvals/{approvalId}",
    database: "(default)",
  },
  async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();
    const {projectId, songId, mixId} = event.params;

    // Only notify if status actually changed
    if (oldData.status === newData.status) {
      console.log("Approval status unchanged - skipping notification");
      return;
    }

    console.log(`Approval status changed to ${newData.status} for mix ${mixId}`);

    try {
      // Get project details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();
      const producerId = projectData.ownerUserId;

      // Don't notify if the producer changed their own approval
      if (newData.reviewerUserId === producerId) {
        console.log("Producer changed their own approval - skipping notification");
        return;
      }

      // Get mix and song details
      const mixDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .collection("mixes")
        .doc(mixId)
        .get();

      const songDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .collection("songs")
        .doc(songId)
        .get();

      const mixName = mixDoc.exists ? mixDoc.data().name : "Mix";
      const songName = songDoc.exists ? songDoc.data().name : "Song";

      // Get reviewer name from the reviewerUserId
      let reviewerName = "An approver";
      if (newData.reviewerUserId) {
        const reviewerUserDoc = await getFirestore()
          .collection("users")
          .doc(newData.reviewerUserId)
          .get();

        if (reviewerUserDoc.exists) {
          reviewerName = reviewerUserDoc.data().displayName || reviewerName;
        }
      }

      // Get producer's FCM tokens (all devices)
      const producerDoc = await getFirestore()
        .collection("users")
        .doc(producerId)
        .get();

      if (!producerDoc.exists) {
        console.log("Producer document not found");
        return;
      }

      const producerData = producerDoc.data();
      const tokens = [];

      // New format: array of tokens for multiple devices
      if (producerData.fcmTokens && Array.isArray(producerData.fcmTokens)) {
        tokens.push(...producerData.fcmTokens);
      }
      // Legacy format: single token (for backward compatibility)
      else if (producerData.fcmToken) {
        tokens.push(producerData.fcmToken);
      }

      if (tokens.length === 0) {
        console.log("Producer has no FCM tokens");
        return;
      }

      // Create appropriate message based on status
      let title, body;
      if (newData.status === "Approved") {
        title = `✅ ${mixName} Approved`;
        body = `${reviewerName} approved ${songName} in ${projectData.name}`;
      } else if (newData.status === "Changes Requested") {
        title = `🔄 Changes Requested: ${mixName}`;
        body = `${reviewerName} requested changes to ${songName} in ${projectData.name}`;
      } else {
        // Pending or other status - skip notification
        return;
      }

      // Send notification to producer (all devices)
      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "approval_status_changed",
          projectId: projectId,
          songId: songId,
          mixId: mixId,
          status: newData.status,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send approval notification to producer (${tokens.length} devices)`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent approval notification: ${response.successCount} succeeded, ${response.failureCount} failed`);
    } catch (error) {
      console.error("Error sending approval notification:", error);
    }
  }
);

/**
 * Send notification when a reviewer is added to a project
 * Notifies the invited reviewer that they've been added to a project
 */
exports.onReviewerAdded = onDocumentCreated(
  {
    document: "projects/{projectId}/reviewers/{reviewerId}",
    database: "(default)",
  },
  async (event) => {
    const reviewerData = event.data.data();
    const {projectId, reviewerId} = event.params;

    console.log(`New reviewer added: ${reviewerId} to project ${projectId}`);

    try {
      // Get project details
      const projectDoc = await getFirestore()
        .collection("projects")
        .doc(projectId)
        .get();

      if (!projectDoc.exists) {
        console.log("Project not found");
        return;
      }

      const projectData = projectDoc.data();

      // Get producer name
      let producerName = "A producer";
      if (projectData.ownerUserId) {
        const producerDoc = await getFirestore()
          .collection("users")
          .doc(projectData.ownerUserId)
          .get();

        if (producerDoc.exists) {
          producerName = producerDoc.data().displayName || producerName;
        }
      }

      // Get reviewer's FCM tokens (all devices)
      const tokens = [];

      // Check if we have a userId (for registered users)
      if (reviewerData.userId) {
        const reviewerUserDoc = await getFirestore()
          .collection("users")
          .doc(reviewerData.userId)
          .get();

        if (reviewerUserDoc.exists) {
          const userData = reviewerUserDoc.data();
          // New format: array of tokens for multiple devices
          if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
            tokens.push(...userData.fcmTokens);
          }
          // Legacy format: single token (for backward compatibility)
          else if (userData.fcmToken) {
            tokens.push(userData.fcmToken);
          }
        }
      }

      if (tokens.length === 0) {
        console.log("Reviewer has no FCM tokens (may not be registered yet)");
        return;
      }

      // Create notification message
      const title = `🎵 New Project: ${projectData.name}`;
      const body = `${producerName} invited you to review their project`;

      // Send notification to reviewer (all devices)
      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "project_invitation",
          projectId: projectId,
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      console.log(`Attempting to send invitation notification to reviewer (${tokens.length} devices)`);
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`Sent invitation notification: ${response.successCount} succeeded, ${response.failureCount} failed`);

      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`Failed to send to token ${idx}:`, resp.error);
          }
        });
      }
    } catch (error) {
      console.error("Error sending reviewer invitation notification:", error);
    }
  }
);
