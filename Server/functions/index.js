const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');

if (!admin.apps.length) {
  admin.initializeApp();
}

const openai = new OpenAI({
  apiKey: functions.config().openai.key,
});

async function sendMessagesToSubscribers() {
  console.log('Function started at:', new Date().toISOString());
  const db = admin.firestore();

  try {
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);

    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);

      for (const subscriberUsername of chatbot.subscribers) {
        const usersSnapshot = await db.collection('users')
          .where('username', '==', subscriberUsername)
          .get();

        if (usersSnapshot.empty) continue;

        const userDoc = usersSnapshot.docs[0];
        const user = userDoc.data();
        const firstName = user.fullname.split(' ')[0];

        let aiMessage;
        try {
          const completion = await openai.chat.completions.create({
            model: "gpt-4",
            messages: [
              {
                role: "system",
                content: "You are a friendly and casual AI helping a group of friends coordinate weekend hangouts."
              },
              {
                role: "user",
                content: `Write a message addressed to ${firstName}, asking about their availability for this weekend. Make it sound natural, upbeat, and brief. Invite them to suggest activities, locations, or timing preferences.`
              }
            ],
            temperature: 0.8
          });

          aiMessage = completion.choices[0].message.content.trim();
        } catch (err) {
          console.error(`Error generating message for ${firstName}:`, err);
          continue;
        }

        const message = {
          id: admin.firestore.Timestamp.now().toMillis().toString(),
          text: aiMessage,
          senderId: chatbot.id,
          timestamp: admin.firestore.Timestamp.now(),
          side: 'bot'
        };

        const chatsSnapshot = await db.collection('chats')
          .where('userId', '==', userDoc.id)
          .where('chatbotId', '==', chatbot.id)
          .get();

        let chatId;
        if (chatsSnapshot.empty) {
          const newChatRef = await db.collection('chats').add({
            userId: userDoc.id,
            chatbotId: chatbot.id,
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
          chatId = newChatRef.id;
        } else {
          const chatRef = chatsSnapshot.docs[0].ref;
          chatId = chatRef.id;
          await chatRef.update({
            lastMessage: message.text,
            updatedAt: admin.firestore.Timestamp.now()
          });
        }

        await db.collection('chats').doc(chatId).collection('messages').add(message);
      }
    }

    console.log('Messages sent successfully');
    return null;
  } catch (error) {
    console.error('Error sending messages:', error);
    throw error;
  }
}

async function checkUserAvailability(messages) {
  try {
    const formattedMessages = messages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');
    
    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "You analyze conversations and determine if a user has indicated they are not available for the weekend plans. Return ONLY 'available' or 'not available' based on your analysis."
        },
        {
          role: "user",
          content: `Conversation history:\n${formattedMessages}\n\nBased on this conversation, has the user clearly indicated they are NOT available for the weekend hangout?`
        }
      ],
      temperature: 0.1
    });

    const response = completion.choices[0].message.content.trim().toLowerCase();
    return response.includes('not available');
  } catch (error) {
    console.error('Error checking user availability:', error);
    return false; // Default to assuming they're available if there's an error
  }
}

async function analyzeChatsAndSuggestOutings() {
  const db = admin.firestore();
  const chatbotsSnapshot = await db.collection('chatbots').get();

  for (const chatbotDoc of chatbotsSnapshot.docs) {
    const chatbot = chatbotDoc.data();
    const chatsSnapshot = await db.collection('chats')
      .where('chatbotId', '==', chatbot.id)
      .get();

    let allMessages = [];
    let unavailableUserIds = [];
    
    // First pass to identify which users are unavailable
    for (const chatDoc of chatsSnapshot.docs) {
      const userId = chatDoc.data().userId;
      const messagesSnapshot = await chatDoc.ref.collection('messages')
        .orderBy('timestamp', 'asc')
        .get();

      const messages = messagesSnapshot.docs.map(doc => doc.data());
      
      // Check if user is available based on their messages
      const isUnavailable = await checkUserAvailability(messages);
      if (isUnavailable) {
        unavailableUserIds.push(userId);
        console.log(`User ${userId} indicated they are not available`);
      } else {
        allMessages = allMessages.concat(messages);
      }
    }

    const formattedMessages = allMessages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');

    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "You are a helpful assistant that analyzes group chat conversations and suggests weekend outing options. Keep it short without compromising important details."
        },
        {
          role: "user",
          content: `Conversation history:\n${formattedMessages}\n\nBased on this, suggest 3-5 outing options including activity, location, and timing. Format your suggestions as a numbered list, where each item includes activity, location (exact address), date, start time, and end time.`
        }
      ],
      temperature: 0.8
    });

    const suggestions = completion.choices[0].message.content.trim();

    // Only send to users who are available
    for (const chatDoc of chatsSnapshot.docs) {
      const userId = chatDoc.data().userId;
      
      // Skip users who indicated they are not available
      if (unavailableUserIds.includes(userId)) {
        console.log(`Skipping suggestions for unavailable user ${userId}`);
        continue;
      }
      
      const userDoc = await db.collection('users').doc(userId).get();
      const user = userDoc.data();

      const message = {
        id: admin.firestore.Timestamp.now().toMillis().toString(),
        text: `Hey ${user.fullname.split(' ')[0]}! Based on our chat, here are some outing ideas:\n\n${suggestions}`,
        senderId: chatbot.id,
        timestamp: admin.firestore.Timestamp.now(),
        side: 'bot'
      };

      await db.collection('chats').doc(chatDoc.id).collection('messages').add(message);
      await chatDoc.ref.update({
        lastMessage: message.text,
        updatedAt: admin.firestore.Timestamp.now()
      });
    }
  }
}

async function analyzeResponsesAndSendFinalPlan() {
  const db = admin.firestore();
  const chatbotsSnapshot = await db.collection('chatbots').get();

  for (const chatbotDoc of chatbotsSnapshot.docs) {
    const chatbot = chatbotDoc.data();
    const chatsSnapshot = await db.collection('chats')
      .where('chatbotId', '==', chatbot.id)
      .get();

    let allMessages = [];
    let unavailableUserIds = [];
    let availableUserNames = [];
    
    // First pass to identify which users are unavailable and collect names of available users
    for (const chatDoc of chatsSnapshot.docs) {
      const userId = chatDoc.data().userId;
      const messagesSnapshot = await chatDoc.ref.collection('messages')
        .orderBy('timestamp', 'asc')
        .get();

      const messages = messagesSnapshot.docs.map(doc => doc.data());
      
      // Check if user is available based on their messages
      const isUnavailable = await checkUserAvailability(messages);
      
      const userDoc = await db.collection('users').doc(userId).get();
      const user = userDoc.data();
      
      if (isUnavailable) {
        unavailableUserIds.push(userId);
      } else {
        availableUserNames.push(user.fullname);
        allMessages = allMessages.concat(messages);
      }
    }

    const formattedMessages = allMessages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');

    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "You analyze group chats to finalize and announce the weekend plan."
        },
        {
          role: "user",
          content: `Conversation history:\n${formattedMessages}\n\nAvailable participants: ${availableUserNames.join(', ')}\n\nBased on this, summarize the final plan including the most agreed upon activity, location, and who is attending.`
        }
      ],
      temperature: 0.7
    });

    const finalPlan = completion.choices[0].message.content.trim();

    // Only send to users who are available
    for (const chatDoc of chatsSnapshot.docs) {
      const userId = chatDoc.data().userId;
      
      // Skip users who indicated they are not available
      if (unavailableUserIds.includes(userId)) {
        console.log(`Skipping final plan for unavailable user ${userId}`);
        continue;
      }
      
      const userDoc = await db.collection('users').doc(userId).get();
      const user = userDoc.data();

      const message = {
        id: admin.firestore.Timestamp.now().toMillis().toString(),
        text: `Hey ${user.fullname.split(' ')[0]}! Here's the final plan for our weekend hangout:\n\n${finalPlan}`,
        senderId: chatbot.id,
        timestamp: admin.firestore.Timestamp.now(),
        side: 'bot'
      };

      await db.collection('chats').doc(chatDoc.id).collection('messages').add(message);
      await chatDoc.ref.update({
        lastMessage: message.text,
        updatedAt: admin.firestore.Timestamp.now()
      });
    }
  }
}

exports.sendWeeklyMessages = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' })
  .pubsub
  .schedule('05 18 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async () => sendMessagesToSubscribers());

exports.suggestWeekendOutings = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' })
  .pubsub
  .schedule('08 18 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async () => analyzeChatsAndSuggestOutings());

exports.sendFinalPlan = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' })
  .pubsub
  .schedule('10 18 * * 1')
  .timeZone('America/Los_Angeles')
  .onRun(async () => analyzeResponsesAndSendFinalPlan());

exports.sendMessagesToSubscribers = sendMessagesToSubscribers;
