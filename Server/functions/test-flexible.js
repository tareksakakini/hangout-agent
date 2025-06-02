const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Import the function from index.js
const { testAnalyzeAndSendMessages } = require('./index');

async function runTest() {
  console.log('Testing the new flexible messaging system...');
  
  try {
    await testAnalyzeAndSendMessages();
    console.log('✅ Test completed successfully!');
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
}

async function testMessageTrigger() {
  console.log('Testing message trigger simulation...');
  
  try {
    const db = admin.firestore();
    
    // Get a sample chat to simulate a message
    const chatsSnapshot = await db.collection('chats').limit(1).get();
    
    if (chatsSnapshot.empty) {
      console.log('No chats found to test with');
      return;
    }
    
    const chatDoc = chatsSnapshot.docs[0];
    console.log(`Simulating user message in chat: ${chatDoc.id}`);
    
    // Simulate adding a user message (this would normally trigger the function)
    const testMessage = {
      id: admin.firestore.Timestamp.now().toMillis().toString(),
      text: 'Hey, are we still on for this weekend?',
      senderId: 'test_user',
      timestamp: admin.firestore.Timestamp.now(),
      side: 'user'
    };
    
    await chatDoc.ref.collection('messages').add(testMessage);
    console.log('✅ Test message added - this should trigger the analysis in production');
    
  } catch (error) {
    console.error('❌ Message trigger test failed:', error);
  }
}

// Run the test if this file is executed directly
if (require.main === module) {
  const testType = process.argv[2] || 'direct';
  
  if (testType === 'trigger') {
    testMessageTrigger();
  } else {
    runTest();
  }
}

module.exports = { runTest, testMessageTrigger }; 