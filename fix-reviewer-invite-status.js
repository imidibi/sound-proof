#!/usr/bin/env node

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin
initializeApp({
  credential: applicationDefault(),
  projectId: 'sound-proof-6096d'
});

const db = getFirestore();

async function fixReviewerInviteStatus() {
  console.log('🔧 Starting to fix missing inviteStatus fields in reviewer documents...\n');

  try {
    // Get all projects
    const projectsSnapshot = await db.collection('projects').get();
    console.log(`📁 Found ${projectsSnapshot.size} projects\n`);

    let totalReviewers = 0;
    let fixedReviewers = 0;

    for (const projectDoc of projectsSnapshot.docs) {
      const projectId = projectDoc.id;
      const projectName = projectDoc.data().name || 'Untitled';
      console.log(`\n📂 Processing project: ${projectName} (${projectId})`);

      // Get all reviewers for this project
      const reviewersSnapshot = await db.collection('projects')
        .document(projectId)
        .collection('reviewers')
        .get();

      console.log(`   Found ${reviewersSnapshot.size} reviewers`);
      totalReviewers += reviewersSnapshot.size;

      for (const reviewerDoc of reviewersSnapshot.docs) {
        const reviewerId = reviewerDoc.id;
        const reviewerData = reviewerDoc.data();
        const displayName = reviewerData.displayName || 'Unknown';

        // Check if inviteStatus field is missing
        if (!reviewerData.inviteStatus) {
          console.log(`   ⚠️  Missing inviteStatus for: ${displayName} (${reviewerId})`);

          // Add inviteStatus field with default value of 'accepted'
          // (reasonable default for existing reviewers who are already in the system)
          await reviewerDoc.ref.update({
            inviteStatus: 'accepted'
          });

          console.log(`   ✅ Fixed: Added inviteStatus='accepted' for ${displayName}`);
          fixedReviewers++;
        } else {
          console.log(`   ✓  ${displayName} already has inviteStatus: ${reviewerData.inviteStatus}`);
        }
      }
    }

    console.log(`\n\n🎉 Migration complete!`);
    console.log(`   Total reviewers processed: ${totalReviewers}`);
    console.log(`   Reviewers fixed: ${fixedReviewers}`);
    console.log(`   Already correct: ${totalReviewers - fixedReviewers}`);

    process.exit(0);
  } catch (error) {
    console.error('❌ Error fixing reviewer data:', error);
    process.exit(1);
  }
}

fixReviewerInviteStatus();
