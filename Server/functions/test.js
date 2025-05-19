const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

// Set environment variables
process.env.GCLOUD_PROJECT = 'hangout-agent';
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: 'hangout-agent'
});

// Initialize Firebase Admin only if it hasn't been initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'hangout-agent'
  });
}

// Import the core function
const { sendMessagesToSubscribers } = require('./index');

// Run the function
sendMessagesToSubscribers()
  .then(() => {
    console.log('Test completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Test failed:', error);
    process.exit(1);
  }); 