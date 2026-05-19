#!/usr/bin/env node

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin
initializeApp({
  credential: applicationDefault(),
  projectId: 'sound-proof-6096d'
});

const db = getFirestore();

async function deleteCollection(collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const query = collectionRef.limit(batchSize);

  return new Promise((resolve, reject) => {
    deleteQueryBatch(query, resolve).catch(reject);
  });
}

async function deleteQueryBatch(query, resolve) {
  const snapshot = await query.get();

  const batchSize = snapshot.size;
  if (batchSize === 0) {
    resolve();
    return;
  }

  console.log(`Deleting ${batchSize} documents from ${query._queryOptions.collectionId}...`);

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  await batch.commit();

  process.nextTick(() => {
    deleteQueryBatch(query, resolve);
  });
}

async function clearAllData() {
  console.log('🗑️  Starting to clear all Firestore data...\n');

  try {
    // Delete all top-level collections
    console.log('Deleting users collection...');
    await deleteCollection('users');
    console.log('✅ Users deleted\n');

    console.log('Deleting projects collection (including all subcollections)...');
    await deleteCollection('projects');
    console.log('✅ Projects deleted\n');

    console.log('Deleting organizations collection...');
    await deleteCollection('organizations');
    console.log('✅ Organizations deleted\n');

    console.log('🎉 All data cleared successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error clearing data:', error);
    process.exit(1);
  }
}

clearAllData();
