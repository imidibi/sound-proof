#!/usr/bin/env node

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin
initializeApp({
  credential: applicationDefault(),
  projectId: 'sound-proof-6096d'
});

const db = getFirestore();

async function createUserIdReviewerDocuments() {
  console.log('🔧 Creating userId-based reviewer documents for dual document structure...\n');

  try {
    // Get all projects
    const projectsSnapshot = await db.collection('projects').get();
    console.log(`📁 Found ${projectsSnapshot.size} projects\n`);

    let totalReviewers = 0;
    let createdDocs = 0;
    let skippedDocs = 0;

    for (const projectDoc of projectsSnapshot.docs) {
      const projectId = projectDoc.id;
      const projectName = projectDoc.data().name || 'Untitled';
      console.log(`\n📂 Processing project: ${projectName} (${projectId})`);

      // Get all reviewers for this project
      const reviewersSnapshot = await db.collection('projects')
        .doc(projectId)
        .collection('reviewers')
        .get();

      console.log(`   Found ${reviewersSnapshot.size} reviewers`);
      totalReviewers += reviewersSnapshot.size;

      for (const reviewerDoc of reviewersSnapshot.docs) {
        const reviewerId = reviewerDoc.id;
        const reviewerData = reviewerDoc.data();
        const displayName = reviewerData.displayName || 'Unknown';
        const userId = reviewerData.userId;

        // Only process if reviewer has a userId and the document ID is NOT the userId
        if (userId && reviewerId !== userId) {
          console.log(`   📝 Reviewer: ${displayName} (UUID: ${reviewerId}, userId: ${userId})`);

          // Check if userId-based document already exists
          const userIdDocRef = db.collection('projects')
            .doc(projectId)
            .collection('reviewers')
            .doc(userId);

          const userIdDoc = await userIdDocRef.get();

          if (userIdDoc.exists) {
            console.log(`   ✓ userId-based document already exists, skipping`);
            skippedDocs++;
          } else {
            // Create the userId-based document with all the same data
            const userIdData = {
              ...reviewerData,
              primaryReviewerId: reviewerId  // Reference to the UUID-based document
            };

            await userIdDocRef.set(userIdData);
            console.log(`   ✅ Created userId-based document: ${userId}`);
            createdDocs++;
          }
        } else if (!userId) {
          console.log(`   ⚠️  ${displayName} has no userId (pending invitation)`);
        } else {
          console.log(`   ✓ ${displayName} document ID is already userId-based`);
          skippedDocs++;
        }
      }
    }

    console.log(`\n\n🎉 Migration complete!`);
    console.log(`   Total reviewers processed: ${totalReviewers}`);
    console.log(`   userId-based documents created: ${createdDocs}`);
    console.log(`   Skipped (already correct): ${skippedDocs}`);

    process.exit(0);
  } catch (error) {
    console.error('❌ Error creating userId-based documents:', error);
    process.exit(1);
  }
}

createUserIdReviewerDocuments();
