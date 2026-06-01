// Quick script to check if a user has FCM tokens
const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'approvl',
});

const userId = 'dZpq4IHtGBYVihU39nDJQzoNROT2'; // testartist3

admin.firestore().collection('users').doc(userId).get()
  .then(doc => {
    if (doc.exists) {
      const data = doc.data();
      console.log('User:', userId);
      console.log('Display Name:', data.displayName);
      console.log('Email:', data.email);
      console.log('FCM Tokens (array):', data.fcmTokens);
      console.log('FCM Token (legacy):', data.fcmToken);
      console.log('');
      console.log('Has tokens:', (data.fcmTokens && data.fcmTokens.length > 0) || !!data.fcmToken);
    } else {
      console.log('User document not found');
    }
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
