const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');

// Initialize Firebase Admin only if it hasn't been initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

// Initialize OpenAI with Firebase config
const openai = new OpenAI({
  apiKey: functions.config().openai.key,
});

// Core function logic separated from the Firebase Functions wrapper
async function sendMessagesToSubscribers() {
  console.log('Function started at:', new Date().toISOString());
  const db = admin.firestore();
  
  try {
    // Get all chatbots
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);
    
    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
      console.log(`Subscribers: ${chatbot.subscribers.join(', ')}`);
      
      // Get all subscribers for this chatbot
      for (const subscriberUsername of chatbot.subscribers) {
        console.log(`Processing subscriber: ${subscriberUsername}`);
        
        // Get user details by username
        const usersSnapshot = await db.collection('users')
          .where('username', '==', subscriberUsername)
          .get();
        
        if (usersSnapshot.empty) {
          console.log(`User with username ${subscriberUsername} not found, skipping`);
          continue;
        }
        
        const userDoc = usersSnapshot.docs[0];
        const user = userDoc.data();
        const firstName = user.fullname.split(' ')[0]; // Get first name
        console.log(`Found user: ${user.fullname} (${firstName})`);
        
        // Create a new message
        const message = {
          id: admin.firestore.Timestamp.now().toMillis().toString(),
          text: `Hey ${firstName}! 👋 I'm planning our weekend hangout. What's your availability looking like? Feel free to share any preferences you have for activities, timing, or location.`,
          senderId: chatbot.id,
          timestamp: admin.firestore.Timestamp.now(),
          side: 'bot'
        };
        
        // Find or create chat
        const chatsSnapshot = await db.collection('chats')
          .where('userId', '==', userDoc.id)
          .where('chatbotId', '==', chatbot.id)
          .get();
        
        let chatId;
        if (chatsSnapshot.empty) {
          console.log(`Creating new chat for user ${userDoc.id} and chatbot ${chatbot.id}`);
          // Create new chat
          const newChatRef = await db.collection('chats').add({
            userId: userDoc.id,
            chatbotId: chatbot.id,
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
          chatId = newChatRef.id;
          console.log(`Created new chat with ID: ${chatId}`);
        } else {
          chatId = chatsSnapshot.docs[0].id;
          console.log(`Found existing chat with ID: ${chatId}`);
          // Update last message
          await chatsSnapshot.docs[0].ref.update({
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
          console.log(`Updated last message in chat ${chatId}`);
        }
        
        // Add message to chat
        await db.collection('chats').doc(chatId).collection('messages').add(message);
        console.log(`Added message to chat ${chatId}`);
      }
    }
    
    console.log('Messages sent successfully');
    return null;
  } catch (error) {
    console.error('Error sending messages:', error);
    console.error('Error stack:', error.stack);
    throw error;
  }
}

// Helper function to determine user availability using OpenAI
async function determineUserAvailability(messages) {
  try {
    const formattedMessages = messages
      .map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`)
      .join('\n');

    const prompt = `
    Analyze the following conversation and determine if the user has indicated they are available for a weekend hangout.
    Consider:
    1. Direct statements about availability
    2. Context of the conversation
    3. Any constraints or limitations mentioned
    4. The tone and certainty of their response

    Respond with ONLY "AVAILABLE" or "NOT_AVAILABLE" based on your analysis.

    Conversation:
    ${formattedMessages}

    Response:`;

    const completion = await openai.chat.completions.create({
      model: "o4-mini-2025-04-16",
      messages: [
        {
          role: "system",
          content: "You are an AI assistant that analyzes conversations to determine if someone is available for a weekend hangout. Respond with only AVAILABLE or NOT_AVAILABLE."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      temperature: 1
    });

    const response = completion.choices[0].message.content.trim();
    return response === "AVAILABLE";
  } catch (error) {
    console.error('Error determining user availability:', error);
    return false; // Default to not available if there's an error
  }
}

// Function to analyze chats and suggest weekend outings
async function analyzeChatsAndSuggestOutings() {
  console.log('Starting chat analysis at:', new Date().toISOString());
  const db = admin.firestore();
  
  try {
    // Get all chatbots
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);
    
    if (chatbotsSnapshot.empty) {
      console.log('No chatbots found in the database');
      return null;
    }
    
    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
      
      if (!chatbot.subscribers || chatbot.subscribers.length === 0) {
        console.log(`No subscribers found for chatbot ${chatbot.id}, skipping`);
        continue;
      }
      
      // Get all chats for this chatbot
      const chatsSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbot.id)
        .get();
      
      console.log(`Found ${chatsSnapshot.size} chats for chatbot ${chatbot.id}`);
      
      if (chatsSnapshot.empty) {
        console.log(`No chats found for chatbot ${chatbot.id}, skipping`);
        continue;
      }
      
      // First, determine who is available using AI analysis
      let availableSubscribers = new Set();
      for (const chatDoc of chatsSnapshot.docs) {
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'desc')
          .limit(20) // Get last 20 messages for better context
          .get();
        
        const messages = messagesSnapshot.docs.map(doc => {
          const data = doc.data();
          return {
            text: data.text,
            senderId: data.senderId,
            timestamp: data.timestamp.toDate(),
            side: data.side
          };
        });
        
        // Use AI to determine availability
        const isAvailable = await determineUserAvailability(messages);
        console.log(`User ${chatDoc.data().userId} availability: ${isAvailable ? 'Available' : 'Not Available'}`);
        
        if (isAvailable) {
          availableSubscribers.add(chatDoc.data().userId);
        }
      }
      
      console.log(`Found ${availableSubscribers.size} available subscribers`);
      
      if (availableSubscribers.size === 0) {
        console.log('No available subscribers found, skipping suggestions');
        continue;
      }
      
      // Collect all messages from available subscribers' chats
      let allMessages = [];
      for (const chatDoc of chatsSnapshot.docs) {
        if (!availableSubscribers.has(chatDoc.data().userId)) {
          continue;
        }
        
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'asc')
          .get();
        
        const messages = messagesSnapshot.docs.map(doc => {
          const data = doc.data();
          return {
            text: data.text,
            senderId: data.senderId,
            timestamp: data.timestamp.toDate(),
            side: data.side
          };
        });
        
        allMessages = allMessages.concat(messages);
      }
      
      console.log(`Total messages collected: ${allMessages.length}`);
      
      if (allMessages.length === 0) {
        console.log('No messages found in any chats, skipping OpenAI analysis');
        continue;
      }
      
      // Format messages for OpenAI
      const formattedMessages = allMessages
        .sort((a, b) => a.timestamp - b.timestamp)
        .map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`)
        .join('\n');
      
      console.log('Formatted messages for OpenAI:', formattedMessages.substring(0, 200) + '...');
      
      // Create prompt for OpenAI
      const prompt = `
      You are an AI assistant analyzing a group chat about weekend plans. Based on the following conversation history, suggest 3-5 potential weekend outing options that would accommodate everyone's preferences and constraints.

      Consider:
      1. Timing preferences
      2. Location preferences
      3. Activity preferences
      4. Any constraints mentioned

      Format your response as a numbered list of options, with each option including:
      - Activity type
      - Suggested timing
      - Location

      Don't be too verbose.

      Conversation History:
      ${formattedMessages}

      Please provide your suggestions:
      `;
      
      console.log('Sending request to OpenAI...');
      
      // Get suggestions from OpenAI
      const completion = await openai.chat.completions.create({
        model: "o4-mini-2025-04-16",
        messages: [
          {
            role: "system",
            content: "You are a helpful assistant that analyzes group chat conversations and suggests weekend outing options based on everyone's preferences and constraints."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        temperature: 1
      });
      
      console.log('Received response from OpenAI');
      
      const suggestions = completion.choices[0].message.content;
      console.log('Generated suggestions:', suggestions.substring(0, 200) + '...');
      
      // Send suggestions only to available subscribers
      for (const subscriberUsername of chatbot.subscribers) {
        const usersSnapshot = await db.collection('users')
          .where('username', '==', subscriberUsername)
          .get();
        
        if (usersSnapshot.empty) {
          console.log(`User with username ${subscriberUsername} not found, skipping`);
          continue;
        }
        
        const userDoc = usersSnapshot.docs[0];
        if (!availableSubscribers.has(userDoc.id)) {
          console.log(`User ${userDoc.id} is not available, skipping`);
          continue;
        }
        
        // Create message with suggestions
        const message = {
          id: admin.firestore.Timestamp.now().toMillis().toString(),
          text: `Hey ${userDoc.data().fullname}! 👋 Based on our group's preferences, here are some weekend outing suggestions:\n\n${suggestions}\n\nWhich ones of these would you be able to join?`,
          senderId: chatbot.id,
          timestamp: admin.firestore.Timestamp.now(),
          side: 'bot'
        };
        
        // Find or create chat
        const chatSnapshot = await db.collection('chats')
          .where('userId', '==', userDoc.id)
          .where('chatbotId', '==', chatbot.id)
          .get();
        
        if (!chatSnapshot.empty) {
          const chatId = chatSnapshot.docs[0].id;
          console.log(`Found existing chat ${chatId} for user ${userDoc.id}`);
          
          // Add message to chat
          await db.collection('chats').doc(chatId).collection('messages').add(message);
          console.log(`Added message to chat ${chatId}`);
          
          // Update last message
          await chatSnapshot.docs[0].ref.update({
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
          console.log(`Updated last message in chat ${chatId}`);
        } else {
          console.log(`No existing chat found for user ${userDoc.id} and chatbot ${chatbot.id}`);
        }
      }
    }
    
    console.log('Analysis and suggestions completed successfully');
    return null;
  } catch (error) {
    console.error('Error analyzing chats:', error);
    console.error('Error stack:', error.stack);
    throw error;
  }
}

// Function to analyze responses and send final plan
async function analyzeResponsesAndSendFinalPlan() {
  console.log('Starting final plan analysis at:', new Date().toISOString());
  const db = admin.firestore();
  
  try {
    // Get all chatbots
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);
    
    if (chatbotsSnapshot.empty) {
      console.log('No chatbots found in the database');
      return null;
    }
    
    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
      
      if (!chatbot.subscribers || chatbot.subscribers.length === 0) {
        console.log(`No subscribers found for chatbot ${chatbot.id}, skipping`);
        continue;
      }
      
      // Get all chats for this chatbot
      const chatsSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbot.id)
        .get();
      
      console.log(`Found ${chatsSnapshot.size} chats for chatbot ${chatbot.id}`);
      
      if (chatsSnapshot.empty) {
        console.log(`No chats found for chatbot ${chatbot.id}, skipping`);
        continue;
      }
      
      // First, determine who is available using AI analysis
      let availableSubscribers = new Map(); // Map of userId to their preferences
      for (const chatDoc of chatsSnapshot.docs) {
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'desc')
          .limit(20) // Get last 20 messages for better context
          .get();
        
        const messages = messagesSnapshot.docs.map(doc => {
          const data = doc.data();
          return {
            text: data.text,
            senderId: data.senderId,
            timestamp: data.timestamp.toDate(),
            side: data.side
          };
        });
        
        // Use AI to determine availability
        const isAvailable = await determineUserAvailability(messages);
        console.log(`User ${chatDoc.data().userId} availability: ${isAvailable ? 'Available' : 'Not Available'}`);
        
        if (isAvailable) {
          // Get user's preferences from their messages
          const preferences = messages
            .filter(msg => msg.side === 'user')
            .map(msg => msg.text)
            .join(' ');
          availableSubscribers.set(chatDoc.data().userId, preferences);
        }
      }
      
      console.log(`Found ${availableSubscribers.size} available subscribers`);
      
      if (availableSubscribers.size === 0) {
        console.log('No available subscribers found, skipping final plan');
        continue;
      }
      
      // Collect all messages from available subscribers' chats
      let allMessages = [];
      for (const chatDoc of chatsSnapshot.docs) {
        if (!availableSubscribers.has(chatDoc.data().userId)) {
          continue;
        }
        
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'asc')
          .get();
        
        const messages = messagesSnapshot.docs.map(doc => {
          const data = doc.data();
          return {
            text: data.text,
            senderId: data.senderId,
            timestamp: data.timestamp.toDate(),
            side: data.side
          };
        });
        
        allMessages = allMessages.concat(messages);
      }
      
      console.log(`Total messages collected: ${allMessages.length}`);
      
      if (allMessages.length === 0) {
        console.log('No messages found in any chats, skipping analysis');
        continue;
      }
      
      // Format messages for OpenAI
      const formattedMessages = allMessages
        .sort((a, b) => a.timestamp - b.timestamp)
        .map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`)
        .join('\n');
      
      console.log('Formatted messages for OpenAI:', formattedMessages.substring(0, 200) + '...');
      
      // Create prompt for OpenAI
      const prompt = `
      You are an AI assistant analyzing a group chat about weekend plans. Based on the following conversation history, determine:
      1. Which weekend plan option was most popular among the group
      2. Which people confirmed they can attend

      Format your response as:
      CHOSEN PLAN: [The most popular option with its details]
      ATTENDEES: [List of people who voted for the chosen plan]

      Keep the response concise and clear.

      Conversation History:
      ${formattedMessages}

      Please provide your analysis:
      `;
      
      console.log('Sending request to OpenAI...');
      
      // Get analysis from OpenAI
      const completion = await openai.chat.completions.create({
        model: "o4-mini-2025-04-16",
        messages: [
          {
            role: "system",
            content: "You are a helpful assistant that analyzes group chat conversations to determine the most popular weekend plan and who can attend."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        temperature: 1
      });
      
      console.log('Received response from OpenAI');
      
      const analysis = completion.choices[0].message.content;
      console.log('Generated analysis:', analysis.substring(0, 200) + '...');
      
      // Send final plan only to available subscribers
      for (const subscriberUsername of chatbot.subscribers) {
        const usersSnapshot = await db.collection('users')
          .where('username', '==', subscriberUsername)
          .get();
        
        if (usersSnapshot.empty) {
          console.log(`User with username ${subscriberUsername} not found, skipping`);
          continue;
        }
        
        const userDoc = usersSnapshot.docs[0];
        if (!availableSubscribers.has(userDoc.id)) {
          console.log(`User ${userDoc.id} is not available, skipping`);
          continue;
        }
        
        // Create message with final plan
        const message = {
          id: admin.firestore.Timestamp.now().toMillis().toString(),
          text: `Hey ${userDoc.data().fullname}! 👋 Here's the final plan for our weekend hangout:\n\n${analysis}\n\nLooking forward to seeing you there!`,
          senderId: chatbot.id,
          timestamp: admin.firestore.Timestamp.now(),
          side: 'bot'
        };
        
        // Find or create chat
        const chatSnapshot = await db.collection('chats')
          .where('userId', '==', userDoc.id)
          .where('chatbotId', '==', chatbot.id)
          .get();
        
        if (!chatSnapshot.empty) {
          const chatId = chatSnapshot.docs[0].id;
          console.log(`Found existing chat ${chatId} for user ${userDoc.id}`);
          
          // Add message to chat
          await db.collection('chats').doc(chatId).collection('messages').add(message);
          console.log(`Added message to chat ${chatId}`);
          
          // Update last message
          await chatSnapshot.docs[0].ref.update({
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
          console.log(`Updated last message in chat ${chatId}`);
        } else {
          console.log(`No existing chat found for user ${userDoc.id} and chatbot ${chatbot.id}`);
        }
      }
    }
    
    console.log('Final plan analysis and messages completed successfully');
    return null;
  } catch (error) {
    console.error('Error analyzing responses:', error);
    console.error('Error stack:', error.stack);
    throw error;
  }
}

// Export the core function for testing
exports.sendMessagesToSubscribers = sendMessagesToSubscribers;

// Export the Firebase Functions
exports.sendWeeklyMessages = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' }) // 👈 Force GCFv2
  .pubsub
  .schedule('30 11 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async (context) => {
    console.log('Starting sendWeeklyMessages function at:', new Date().toISOString());
    return sendMessagesToSubscribers();
  });

exports.suggestWeekendOutings = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' }) // 👈 Force GCFv2
  .pubsub
  .schedule('35 11 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async (context) => {
    console.log('Starting suggestWeekendOutings function at:', new Date().toISOString());
    return analyzeChatsAndSuggestOutings();
  });

exports.sendFinalPlan = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' }) // 👈 Force GCFv2
  .pubsub
  .schedule('40 11 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async (context) => {
    console.log('Starting sendFinalPlan function at:', new Date().toISOString());
    return analyzeResponsesAndSendFinalPlan();
  });
