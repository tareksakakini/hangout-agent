const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { OpenAI } = require('openai');

admin.initializeApp();
const db = admin.firestore();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || functions.config().openai?.key,
});

// Function to generate the system prompt
async function generateSystemPrompt(chatId) {
  const chatDoc = await db.collection('chats').doc(chatId).get();
  const chatData = chatDoc.data();
  if (!chatData) {
    throw new Error(`Chat with ID ${chatId} not found.`);
  }
  const chatbotId = chatData.chatbotId;
  const userId = chatData.userId;

  console.log(`Chat data:`, chatData);
  console.log(`Chatbot ID: ${chatbotId}, User ID: ${userId}`);

  // Fetch chatbot details
  const chatbotDoc = await db.collection('chatbots').doc(chatbotId).get();
  const chatbotData = chatbotDoc.data();
  if (!chatbotData) {
    throw new Error(`Chatbot with ID ${chatbotId} not found.`);
  }
  const chatbotName = chatbotData.name;
  const subscribers = chatbotData.subscribers || [];
  const planningStartDate = chatbotData.planningStartDate;
  const planningEndDate = chatbotData.planningEndDate;

  console.log(`Chatbot data:`, chatbotData);
  console.log(`Subscribers:`, subscribers);

  // Fetch user details
  const userDoc = await db.collection('users').doc(userId).get();
  const userData = userDoc.data();
  if (!userData) {
    throw new Error(`User with ID ${userId} not found.`);
  }
  const userName = userData.fullname;
  const userUsername = userData.username;
  const userTimezone = userData.timezone || 'UTC'; // Default to UTC if no timezone stored

  console.log(`User data:`, userData);
  console.log(`User timezone: ${userTimezone}`);

  // Generate date and time in user's timezone
  const now = new Date();
  const today = now.toLocaleDateString('en-CA', { timeZone: userTimezone }); // YYYY-MM-DD format
  const currentTime = now.toLocaleTimeString('en-US', { 
    timeZone: userTimezone,
    hour12: true,
    hour: 'numeric',
    minute: '2-digit'
  });

  // Format planning date range in user's timezone
  let planningDateRange = 'No specific date range set';
  if (planningStartDate && planningEndDate) {
    const startDate = planningStartDate.toDate();
    const endDate = planningEndDate.toDate();
    
    const formattedStartDate = startDate.toLocaleDateString('en-US', { 
      timeZone: userTimezone,
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
    
    const formattedEndDate = endDate.toLocaleDateString('en-US', { 
      timeZone: userTimezone,
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
    
    if (startDate.toDateString() === endDate.toDateString()) {
      // Same day
      planningDateRange = formattedStartDate;
    } else {
      // Date range
      planningDateRange = `${formattedStartDate} through ${formattedEndDate}`;
    }
  }

  console.log(`Planning date range: ${planningDateRange}`);

  // Fetch details of users subscribed to this chatbot
  const groupMembers = [];
  for (const subscriberId of subscribers) {
    console.log(`Fetching subscriber: ${subscriberId}`);
    
    // First try fetching by document ID (assuming subscriberId is a user ID)
    let subscriberDoc = await db.collection('users').doc(subscriberId).get();
    let subscriberData = subscriberDoc.data();
    
    // If not found by ID, try querying by username
    if (!subscriberData) {
      console.log(`Subscriber not found by ID ${subscriberId}, trying username search...`);
      const usernameQuery = await db.collection('users').where('username', '==', subscriberId).get();
      if (!usernameQuery.empty) {
        subscriberDoc = usernameQuery.docs[0];
        subscriberData = subscriberDoc.data();
        console.log(`Found subscriber by username: ${subscriberId}`);
      }
    }
    
    if (!subscriberData) {
      console.error(`Subscriber with ID/username ${subscriberId} not found.`);
      throw new Error(`Subscriber with ID/username ${subscriberId} not found.`);
    }
    if (!subscriberData.fullname || !subscriberData.username) {
      console.error(`Subscriber ${subscriberId} missing required fields:`, subscriberData);
      throw new Error(`Subscriber ${subscriberId} missing required fields (fullname or username).`);
    }
    groupMembers.push({
      name: subscriberData.fullname,
      username: subscriberData.username,
      homeCity: subscriberData.homeCity || 'Unknown'
    });
    console.log(`Added subscriber: ${subscriberData.fullname} (${subscriberData.username})`);
  }

  console.log(`Group members:`, groupMembers);

  // Create a mapping of user IDs to names for chat history
  const userIdToNameMap = {};
  
  // Add current user to the mapping
  userIdToNameMap[userId] = userName;
  
  // Add all subscribers to the mapping
  for (const subscriberId of subscribers) {
    let subscriberDoc = await db.collection('users').doc(subscriberId).get();
    let subscriberData = subscriberDoc.data();
    
    if (!subscriberData) {
      const usernameQuery = await db.collection('users').where('username', '==', subscriberId).get();
      if (!usernameQuery.empty) {
        subscriberDoc = usernameQuery.docs[0];
        subscriberData = subscriberDoc.data();
      }
    }
    
    if (subscriberData && subscriberData.fullname) {
      userIdToNameMap[subscriberDoc.id] = subscriberData.fullname;
      userIdToNameMap[subscriberData.username] = subscriberData.fullname; // Handle both ID and username
    }
  }
  
  // Add chatbot to the mapping
  userIdToNameMap['chatbot'] = chatbotName;
  
  console.log('User ID to Name mapping:', userIdToNameMap);

  // Fetch chat history from all chats with this chatbot (excluding current user's chat)
  const allChatsSnapshot = await db.collection('chats').where('chatbotId', '==', chatbotId).get();
  const chatHistoryByUser = {};
  
  for (const chatDoc of allChatsSnapshot.docs) {
    // Skip the current user's chat since it's included later
    if (chatDoc.id === chatId) continue;
    
    const chatData = chatDoc.data();
    const chatUserId = chatData.userId;
    const chatUserName = userIdToNameMap[chatUserId] || `User ${chatUserId}`;
    
    const messagesSnapshot = await db.collection('chats').doc(chatDoc.id).collection('messages').orderBy('timestamp', 'asc').limit(10).get();
    const userMessages = [];
    
    messagesSnapshot.docs.forEach(messageDoc => {
      const data = messageDoc.data();
      if (data.timestamp && data.text && data.senderId) {
        const senderName = userIdToNameMap[data.senderId] || data.senderId;
        userMessages.push({
          sender: senderName,
          text: data.text,
          timestamp: data.timestamp.toDate()
        });
      }
    });
    
    if (userMessages.length > 0) {
      chatHistoryByUser[chatUserName] = userMessages;
    }
  }

  // Format chat history by user
  const formattedChatHistory = Object.entries(chatHistoryByUser)
    .map(([userName, messages]) => {
      const messageList = messages
        .map(msg => `  [${msg.timestamp.toLocaleString('en-US', { timeZone: userTimezone })}] ${msg.sender}: ${msg.text}`)
        .join('\n');
      return `${userName}'s conversation:\n${messageList}`;
    })
    .join('\n\n');

  return `
YOUR ROLE:
    
You are a friendly and helpful AI assistant coordinating hangouts for a group of friends. Your goal is to gather information about availability and preferences for the specified planning period. Your goal is not to suggest options.

Group Members:
${groupMembers.map(member => `- ${member.name} (${member.username}) from ${member.homeCity}`).join('\n')}

PLANNING DATE RANGE: ${planningDateRange}

Your job is to:
1. Gather availability information for the planning date range: ${planningDateRange}
2. Collect preferences about:
    - Preferred timing (morning, afternoon, evening, or specific times)
    - Location preferences or constraints
    - Activity preferences (indoor/outdoor, active/relaxed, etc.)

CONVERSATION GUIDELINES:
1. Be friendly and conversational
2. Ask one question at a time to avoid overwhelming users
3. Don't be pushy - if a user does not express any preferences, wrap up the conversation and inform the user that they can share any preferences at any time in the future
4. Acknowledge and validate preferences
5. Reference the specific planning date range (${planningDateRange}) when asking about availability

Current Date: ${today}
Current Time: ${currentTime}

Other Conversations:
${formattedChatHistory || 'No other conversations yet.'}

Current User:
- ${userName} (${userUsername})
`;
}

// Firestore trigger: on new user message, generate bot reply
exports.onMessageCreate = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const chatId = context.params.chatId;

    // Only respond to user messages
    if (!message || message.side !== 'user') return null;

    try {
      // Fetch last 10 messages for context, ordered by timestamp
      const messagesSnap = await db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', 'desc')
        .limit(10)
        .get();

      // Reverse to chronological order
      const chatHistory = [];
      messagesSnap.docs.reverse().forEach(doc => {
        const m = doc.data();
        if (m && m.text && m.side) {
          chatHistory.push({
            role: m.side === 'user' ? 'user' : 'assistant',
            content: m.text,
          });
        }
      });

      // Add the latest user message if not already present
      if (
        chatHistory.length === 0 ||
        chatHistory[chatHistory.length - 1].content !== message.text
      ) {
        chatHistory.push({ role: 'user', content: message.text });
      }

      // Construct the prompt (generalizable for future expansion)
      const prompt = [
        { role: 'system', content: await generateSystemPrompt(chatId) },
        ...chatHistory
      ];

      // Log the exact prompt sent to OpenAI
      console.log('OpenAI prompt:', JSON.stringify(prompt, null, 2));

      // Call OpenAI
      const completion = await openai.chat.completions.create({
        model: 'gpt-3.5-turbo',
        messages: prompt,
        max_tokens: 256,
        temperature: 0.7,
      });
      const reply = completion.choices[0]?.message?.content?.trim();
      if (!reply) return null;

      // Write bot response as a new message
      const botMessage = {
        id: admin.firestore().collection('_').doc().id,
        text: reply,
        senderId: 'chatbot',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        side: 'bot',
      };
      await db.collection('chats').doc(chatId).collection('messages').doc(botMessage.id).set(botMessage);
      return true;
    } catch (err) {
      console.error('Error generating bot reply:', err);
      return null;
    }
  });
