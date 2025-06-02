const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');

if (!admin.apps.length) {
  admin.initializeApp();
}

const openai = new OpenAI({
  apiKey: functions.config().openai.key,
});

// Add a collection of fallback image URLs by activity type
const FALLBACK_IMAGES = {
  default: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/default_event.jpg?alt=media",
  dining: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/dining.jpg?alt=media",
  hiking: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/hiking.jpg?alt=media", 
  movie: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/movie.jpg?alt=media",
  concert: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/concert.jpg?alt=media",
  beach: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/beach.jpg?alt=media",
  park: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/park.jpg?alt=media",
  coffee: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/coffee.jpg?alt=media",
  sports: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/sports.jpg?alt=media",
  bowling: "https://firebasestorage.googleapis.com/v0/b/hangout-app-123.appspot.com/o/bowling.jpg?alt=media"
};

function getFallbackImageForActivity(activity) {
  const activityLower = activity.toLowerCase();
  
  // Check for relevant keywords in the activity
  if (activityLower.includes('dinner') || activityLower.includes('lunch') || 
      activityLower.includes('brunch') || activityLower.includes('restaurant')) {
    return FALLBACK_IMAGES.dining;
  } else if (activityLower.includes('hike') || activityLower.includes('hiking') || 
             activityLower.includes('trail')) {
    return FALLBACK_IMAGES.hiking;
  } else if (activityLower.includes('movie') || activityLower.includes('cinema') || 
             activityLower.includes('film')) {
    return FALLBACK_IMAGES.movie;
  } else if (activityLower.includes('concert') || activityLower.includes('music') || 
             activityLower.includes('show')) {
    return FALLBACK_IMAGES.concert;
  } else if (activityLower.includes('beach') || activityLower.includes('ocean') || 
             activityLower.includes('coast')) {
    return FALLBACK_IMAGES.beach;
  } else if (activityLower.includes('park') || activityLower.includes('garden') || 
             activityLower.includes('picnic')) {
    return FALLBACK_IMAGES.park;
  } else if (activityLower.includes('coffee') || activityLower.includes('cafe') || 
             activityLower.includes('tea')) {
    return FALLBACK_IMAGES.coffee;
  } else if (activityLower.includes('sport') || activityLower.includes('game') || 
             activityLower.includes('play')) {
    return FALLBACK_IMAGES.sports;
  } else if (activityLower.includes('bowl') || activityLower.includes('bowling')) {
    return FALLBACK_IMAGES.bowling;
  }
  
  return FALLBACK_IMAGES.default;
}

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

async function getImageForActivity(activity) {
  try {
    console.log(`Generating image for activity: ${activity}`);
    
    // Set a timeout for the image generation (20 seconds)
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('Image generation timed out')), 20000)
    );
    
    const imagePromise = openai.images.generate({
      model: "dall-e-3",
      prompt: `Create a vibrant, appealing image representing a group of friends enjoying this activity: ${activity}. Show people having fun in a clean, well-lit environment. No text overlay. Lifestyle photography style.`,
      n: 1,
      size: "1024x1024",
    });
    
    // Race the image generation against the timeout
    const completion = await Promise.race([imagePromise, timeoutPromise]);
    
    console.log('Successfully generated image');
    return completion.data[0].url;
  } catch (error) {
    console.error('Error generating image:', error);
    console.error('Error details:', JSON.stringify(error));
    console.log('Using fallback image for activity');
    return getFallbackImageForActivity(activity);
  }
}

async function parseEventDetails(text) {
  try {
    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "Extract the structured details from the event description. Your response must ONLY contain a valid JSON object with no additional text or markdown formatting."
        },
        {
          role: "user",
          content: `Extract the following details from this event description as a JSON object with these keys: 
          "activity" (the main activity), 
          "location" (the specific location/address), 
          "date" (format: YYYY-MM-DD), 
          "startTime" (format: HH:MM), 
          "endTime" (format: HH:MM), 
          "description" (a brief 1-2 sentence description).
          
          Here's the event text:
          ${text}
          
          Return ONLY the JSON object with no additional explanation or markdown formatting.`
        }
      ],
      temperature: 0.1
    });

    const content = completion.choices[0].message.content.trim();
    // Extract JSON even if there's unexpected text around it
    const jsonMatch = content.match(/(\{.*\})/s);
    if (jsonMatch && jsonMatch[0]) {
      return JSON.parse(jsonMatch[0]);
    }
    
    // Fallback if we can't extract JSON
    return {
      activity: text.substring(0, 50),
      location: "See description for details",
      date: "TBD",
      startTime: "TBD",
      endTime: "TBD",
      description: text
    };
  } catch (error) {
    console.error('Error parsing event details:', error);
    // Return a default format if parsing fails
    return {
      activity: text.substring(0, 50),
      location: "See description for details",
      date: "TBD",
      startTime: "TBD",
      endTime: "TBD",
      description: text
    };
  }
}

async function createEventCard(eventData) {
  try {
    console.log(`Creating event card for activity: ${eventData.activity}`);
    const imageUrl = await getImageForActivity(eventData.activity);
    
    return {
      type: "eventCard",
      activity: eventData.activity,
      location: eventData.location,
      date: eventData.date,
      startTime: eventData.startTime,
      endTime: eventData.endTime,
      description: eventData.description,
      imageUrl: imageUrl || getFallbackImageForActivity(eventData.activity),
    };
  } catch (error) {
    console.error('Error creating event card:', error);
    // Return a card with fallback image if there's an error
    return {
      type: "eventCard",
      activity: eventData.activity,
      location: eventData.location,
      date: eventData.date,
      startTime: eventData.startTime,
      endTime: eventData.endTime,
      description: eventData.description,
      imageUrl: getFallbackImageForActivity(eventData.activity),
    };
  }
}

async function analyzeChatsAndDecideMessages() {
  console.log('Starting flexible message analysis function');
  const db = admin.firestore();
  
  try {
    console.log('Fetching chatbots');
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);

    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
      
      // Get all chats for this chatbot
      const chatsSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbot.id)
        .get();
      console.log(`Found ${chatsSnapshot.size} chats for chatbot: ${chatbot.id}`);

      // Collect chat histories for all users
      const userChatHistories = [];
      
      for (const chatDoc of chatsSnapshot.docs) {
        const userId = chatDoc.data().userId;
        console.log(`Processing chat with userId: ${userId}`);
        
        // Get user info
        const userDoc = await db.collection('users').doc(userId).get();
        const user = userDoc.data();
        
        // Get messages for this chat
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'asc')
          .get();
        console.log(`Found ${messagesSnapshot.size} messages for chat: ${chatDoc.id}`);

        const messages = messagesSnapshot.docs.map(doc => doc.data());
        
        // Format message history for analysis
        const formattedMessages = messages.map(msg => 
          `${msg.side === 'bot' ? 'Agent' : user.fullname.split(' ')[0]}: ${msg.text || '[Event Card]'}`
        ).join('\n');
        
        userChatHistories.push({
          userId,
          chatId: chatDoc.id,
          user,
          messages,
          formattedMessages,
          lastMessageTimestamp: messages.length > 0 ? messages[messages.length - 1].timestamp : null
        });
      }

      if (userChatHistories.length === 0) {
        console.log('No chat histories found, skipping');
        continue;
      }

      // Prepare context for AI analysis
      const allChatHistories = userChatHistories.map(chat => 
        `User ID: ${chat.userId}
User: ${chat.user.fullname} (@${chat.user.username})
Chat History:
${chat.formattedMessages || 'No messages yet'}
`
      ).join('\n---\n');

      // Get current date information
      const now = new Date();
      const currentDateString = now.toLocaleDateString('en-US', { 
        weekday: 'long', 
        year: 'numeric', 
        month: 'long', 
        day: 'numeric' 
      });
      
      // Calculate next weekend dates
      const currentDayOfWeek = now.getDay(); // 0 = Sunday, 6 = Saturday
      let daysUntilSaturday = (6 - currentDayOfWeek) % 7;
      let daysUntilSunday = (7 - currentDayOfWeek) % 7;
      
      if (currentDayOfWeek === 0) { // Sunday
        daysUntilSaturday = 6;
        daysUntilSunday = 7;
      } else if (currentDayOfWeek === 6) { // Saturday
        daysUntilSaturday = 7;
        daysUntilSunday = 1;
      }
      
      const nextSaturday = new Date(now);
      nextSaturday.setDate(now.getDate() + daysUntilSaturday);
      const nextSunday = new Date(now);
      nextSunday.setDate(now.getDate() + daysUntilSunday);
      
      const nextSaturdayFormatted = nextSaturday.toISOString().split('T')[0];
      const nextSundayFormatted = nextSunday.toISOString().split('T')[0];

      // Ask AI to analyze and decide on messages for each user
      console.log('Calling OpenAI to analyze chat histories and decide on messages');
      try {
        const completion = await openai.chat.completions.create({
          model: "gpt-4",
          messages: [
            {
              role: "system",
              content: `You are a social coordination agent that helps groups plan weekend hangouts. 

Your job is to analyze chat histories with different users and decide what action to take for each user. For each user, you need to determine:
1. Whether to send a message or not
2. If sending a message, what type and content

Current context:
- Today is ${currentDateString}
- Next weekend dates: Saturday ${nextSaturdayFormatted}, Sunday ${nextSundayFormatted}

Message types you can send:
- AVAILABILITY_CHECK: Ask about weekend availability and preferences
- SUGGESTIONS: Provide specific activity suggestions with details (activity, location, date, time)
- FINAL_PLAN: Share the decided plan and create group chat
- FOLLOW_UP: Ask for more details, clarify preferences, or keep conversation going
- NONE: Don't send any message

For SUGGESTIONS, format each suggestion with: Activity, Location (with address), Date (YYYY-MM-DD), Start Time, End Time, Description.

IMPORTANT: Use the exact "User ID" value provided in the chat histories for the "userId" field in your response.

Return your response as a JSON object with this structure:
{
  "decisions": [
    {
      "userId": "exact_user_id_from_chat_histories",
      "userName": "User Name",
      "shouldSendMessage": true/false,
      "messageType": "AVAILABILITY_CHECK|SUGGESTIONS|FINAL_PLAN|FOLLOW_UP|NONE",
      "messageContent": "The actual message text to send",
      "reasoning": "Brief explanation of why this decision was made"
    }
  ]
}`
            },
            {
              role: "user",
              content: `Please analyze these chat histories and decide what messages (if any) to send to each user:

${allChatHistories}

For each user, decide:
1. Should I send a message? (Consider: time since last interaction, conversation state, weekend planning progress)
2. What type of message? (availability check, suggestions, final plan, follow-up, or none)
3. What should the message say?

Return ONLY a valid JSON object with your decisions.`
            }
          ],
          temperature: 0.3
        });

        console.log('Successfully received decisions from OpenAI');
        const decisionsText = completion.choices[0].message.content.trim();
        
        // Parse the JSON response
        let decisions;
        try {
          // Extract JSON even if there's unexpected text around it
          const jsonMatch = decisionsText.match(/(\{.*\})/s);
          if (jsonMatch && jsonMatch[0]) {
            decisions = JSON.parse(jsonMatch[0]);
          } else {
            decisions = JSON.parse(decisionsText);
          }
        } catch (parseError) {
          console.error('Error parsing OpenAI response:', parseError);
          console.log('Raw response:', decisionsText);
          continue;
        }

        if (!decisions || !decisions.decisions || !Array.isArray(decisions.decisions)) {
          console.error('Invalid decision structure from OpenAI');
          continue;
        }

        console.log(`Processing ${decisions.decisions.length} message decisions`);

        // Execute the decisions
        for (const decision of decisions.decisions) {
          console.log(`Processing decision for user ${decision.userName}: ${decision.messageType}`);
          console.log(`Reasoning: ${decision.reasoning}`);
          
          if (!decision.shouldSendMessage || decision.messageType === 'NONE') {
            console.log(`Skipping message for ${decision.userName}`);
            continue;
          }

          // Find the user's chat
          const userChat = userChatHistories.find(chat => chat.userId === decision.userId);
          if (!userChat) {
            console.error(`Could not find chat for user ${decision.userId}`);
            continue;
          }

          try {
            if (decision.messageType === 'SUGGESTIONS') {
              // Parse suggestions and create event cards
              await handleSuggestionMessage(db, userChat, decision.messageContent, chatbot.id, nextSaturdayFormatted, nextSundayFormatted);
            } else if (decision.messageType === 'FINAL_PLAN') {
              // Handle final plan with group creation
              await handleFinalPlanMessage(db, userChat, decision.messageContent, chatbot.id, userChatHistories);
            } else {
              // Handle regular text messages (AVAILABILITY_CHECK, FOLLOW_UP)
              await handleRegularMessage(db, userChat, decision.messageContent, chatbot.id);
            }
            
            console.log(`Successfully sent ${decision.messageType} message to ${decision.userName}`);
          } catch (error) {
            console.error(`Error sending message to user ${decision.userId}:`, error);
          }
        }

      } catch (error) {
        console.error('Error calling OpenAI or processing decisions:', error);
      }
    }

    console.log('Flexible message analysis completed successfully');
    return null;
  } catch (error) {
    console.error('Error in analyzeChatsAndDecideMessages:', error);
    throw error;
  }
}

async function handleRegularMessage(db, userChat, messageContent, chatbotId) {
  const message = {
    id: admin.firestore.Timestamp.now().toMillis().toString(),
    text: messageContent,
    senderId: chatbotId,
    timestamp: admin.firestore.Timestamp.now(),
    side: 'bot'
  };

  await db.collection('chats').doc(userChat.chatId).collection('messages').add(message);
  await db.collection('chats').doc(userChat.chatId).update({
    lastMessage: messageContent.substring(0, 100) + (messageContent.length > 100 ? '...' : ''),
    updatedAt: admin.firestore.Timestamp.now()
  });
}

async function handleSuggestionMessage(db, userChat, messageContent, chatbotId, nextSaturdayFormatted, nextSundayFormatted) {
  // Send intro message
  const introMessage = {
    id: admin.firestore.Timestamp.now().toMillis().toString(),
    text: `Hey ${userChat.user.fullname.split(' ')[0]}! Here are some outing ideas for the weekend:`,
    senderId: chatbotId,
    timestamp: admin.firestore.Timestamp.now(),
    side: 'bot'
  };
  await db.collection('chats').doc(userChat.chatId).collection('messages').add(introMessage);

  // Parse suggestions from the message content and create event cards
  const suggestionParagraphs = messageContent.split(/\n\n+/);
  const eventCards = [];
  
  for (const paragraph of suggestionParagraphs) {
    if (paragraph.trim().length > 0) {
      try {
        const eventData = await parseEventDetails(paragraph);
        const eventCard = await createEventCard(eventData);
        eventCards.push(eventCard);
        
        // Send each event card as a separate message
        const cardMessage = {
          id: admin.firestore.Timestamp.now().toMillis().toString(),
          eventCard: eventCard,
          senderId: chatbotId,
          timestamp: admin.firestore.Timestamp.now(),
          side: 'bot'
        };
        await db.collection('chats').doc(userChat.chatId).collection('messages').add(cardMessage);
      } catch (error) {
        console.error(`Error processing suggestion: ${error}`);
      }
    }
  }

  // Update chat's last message
  await db.collection('chats').doc(userChat.chatId).update({
    lastMessage: `${eventCards.length} weekend suggestions`,
    updatedAt: admin.firestore.Timestamp.now()
  });
}

async function handleFinalPlanMessage(db, userChat, messageContent, chatbotId, userChatHistories) {
  // Extract event details from the final plan message
  try {
    const eventData = await parseEventDetails(messageContent);
    const eventCard = await createEventCard(eventData);
    
    // Get all available users for the group
    const availableUsers = [];
    for (const chat of userChatHistories) {
      const isUnavailable = await checkUserAvailability(chat.messages);
      if (!isUnavailable) {
        availableUsers.push({
          userId: chat.userId,
          userName: chat.user.fullname
        });
      }
    }
    
    eventCard.attendees = availableUsers.map(u => u.userName);

    // Create a group for the attendees
    const groupId = `group_${chatbotId}_${admin.firestore.Timestamp.now().toMillis()}`;
    const groupName = `${eventCard.activity} Group`;
    
    await db.collection('groups').doc(groupId).set({
      id: groupId,
      name: groupName,
      participants: availableUsers.map(u => u.userId),
      participantNames: availableUsers.map(u => u.userName),
      createdAt: admin.firestore.Timestamp.now(),
      eventDetails: eventCard,
      lastMessage: null,
      updatedAt: admin.firestore.Timestamp.now()
    });
    
    console.log(`Created group ${groupId} for event: ${eventCard.activity}`);
    
    // Send welcome message to the group
    const welcomeMessage = {
      id: admin.firestore.Timestamp.now().toMillis().toString(),
      text: `Welcome to the ${eventCard.activity} group! Use this chat to coordinate and discuss the event details.`,
      senderId: 'system',
      senderName: 'System',
      timestamp: admin.firestore.Timestamp.now()
    };
    
    await db.collection('groups').doc(groupId).collection('messages').add(welcomeMessage);
    await db.collection('groups').doc(groupId).update({
      lastMessage: welcomeMessage.text,
      updatedAt: admin.firestore.Timestamp.now()
    });

    // Send intro message and event card to the user
    const introMessage = {
      id: admin.firestore.Timestamp.now().toMillis().toString(),
      text: `Hey ${userChat.user.fullname.split(' ')[0]}! Based on everyone's preferences, here's the plan we're going with. A group chat has been created for everyone attending to coordinate!`,
      senderId: chatbotId,
      timestamp: admin.firestore.Timestamp.now(),
      side: 'bot'
    };
    await db.collection('chats').doc(userChat.chatId).collection('messages').add(introMessage);
    
    const cardMessage = {
      id: admin.firestore.Timestamp.now().toMillis().toString(),
      eventCard: eventCard,
      senderId: chatbotId,
      timestamp: admin.firestore.Timestamp.now(),
      side: 'bot'
    };
    await db.collection('chats').doc(userChat.chatId).collection('messages').add(cardMessage);
    
    await db.collection('chats').doc(userChat.chatId).update({
      lastMessage: `Final plan: ${eventCard.activity}`,
      updatedAt: admin.firestore.Timestamp.now()
    });
    
  } catch (error) {
    console.error('Error handling final plan message:', error);
    // Fallback to regular message
    await handleRegularMessage(db, userChat, messageContent, chatbotId);
  }
}

// New trigger-based function that activates when users send messages
exports.onMessageSent = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540, // 9 minutes (maximum timeout)
    memory: '1GB' // Increase memory allocation
  })
  .firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const chatId = context.params.chatId;
    
    // Only trigger on user messages, not bot messages
    if (message.side === 'bot') {
      console.log('Ignoring bot message');
      return null;
    }
    
    console.log(`User message detected in chat ${chatId}, checking if analysis should run`);
    
    try {
      const db = admin.firestore();
      
      // Get the chat document to find the chatbot
      const chatDoc = await db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        console.log('Chat document not found');
        return null;
      }
      
      const chatData = chatDoc.data();
      const chatbotId = chatData.chatbotId;
      
      // Check if we should run analysis for this chatbot
      const shouldAnalyze = await shouldRunAnalysis(db, chatbotId, chatId);
      
      if (shouldAnalyze) {
        console.log(`Running flexible message analysis triggered by user message in chat ${chatId}`);
        await analyzeChatsAndDecideMessages();
      } else {
        console.log('Analysis skipped - bot was the last to message in this chat recently');
      }
      
      return null;
    } catch (error) {
      console.error('Error in message trigger:', error);
      return null;
    }
  });

// Helper function to determine if we should run analysis
async function shouldRunAnalysis(db, chatbotId, triggeringChatId) {
  try {
    // Check the last message in the specific chat that triggered this
    const chatMessagesSnapshot = await db.collection('chats')
      .doc(triggeringChatId)
      .collection('messages')
      .orderBy('timestamp', 'desc')
      .limit(2) // Get last 2 messages to compare
      .get();
    
    if (!chatMessagesSnapshot.empty) {
      const messages = chatMessagesSnapshot.docs.map(doc => doc.data());
      const lastMessage = messages[0];
      
      // If the bot was the last one to send a message in this chat
      if (lastMessage.side === 'bot') {
        const now = new Date();
        const lastMessageTime = lastMessage.timestamp.toDate();
        const timeSinceLastBotMessage = (now - lastMessageTime) / (1000 * 60); // minutes
        
        // If the bot sent a message recently (within 30 minutes), don't double-message
        const minimumIntervalMinutes = 30;
        if (timeSinceLastBotMessage < minimumIntervalMinutes) {
          console.log(`Bot was the last to message in chat ${triggeringChatId} ${timeSinceLastBotMessage.toFixed(1)} minutes ago - preventing double messaging`);
          return false;
        }
      }
    }
    
    // Check if it's within reasonable hours (8 AM to 11 PM Pacific)
    const now = new Date();
    const pacificTime = new Date(now.toLocaleString("en-US", {timeZone: "America/Los_Angeles"}));
    const hour = pacificTime.getHours();
    
    if (hour < 8 || hour > 23) {
      console.log(`Current hour (${hour}) is outside of active hours (8 AM - 11 PM Pacific)`);
      return false;
    }
    
    // Update the analysis history for tracking purposes (but this doesn't block analysis)
    await db.collection('analysisHistory').doc(chatbotId).set({
      lastRun: admin.firestore.Timestamp.now(),
      triggeredBy: 'user_message',
      triggeringChatId: triggeringChatId
    });
    
    return true;
  } catch (error) {
    console.error('Error checking analysis conditions:', error);
    // Default to allowing analysis if there's an error checking conditions
    return true;
  }
}

// Manual trigger function for testing
exports.manualAnalyzeAndSendMessages = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540,
    memory: '1GB'
  })
  .https
  .onRequest(async (req, res) => {
    try {
      console.log('Manual analysis triggered via HTTP request');
      await analyzeChatsAndDecideMessages();
      res.status(200).send('Analysis completed successfully');
    } catch (error) {
      console.error('Manual analysis failed:', error);
      res.status(500).send(`Analysis failed: ${error.message}`);
    }
  });

// Keep the old exports for backward compatibility but comment them out
// exports.sendWeeklyMessages = functions
//   .region('us-central1')
//   .runWith({ platform: 'gcfv2' })
//   .pubsub
//   .schedule('06 19 * * 5')
//   .timeZone('America/Los_Angeles')
//   .onRun(async () => sendMessagesToSubscribers());

// exports.suggestWeekendOutings = functions
//   .region('us-central1')
//   .runWith({
//     platform: 'gcfv2',
//     timeoutSeconds: 540, // 9 minutes (maximum timeout)
//     memory: '1GB' // Increase memory allocation
//   })
//   .pubsub
//   .schedule('09 19 * * 5')
//   .timeZone('America/Los_Angeles')
//   .onRun(async () => analyzeChatsAndSuggestOutings());

// exports.sendFinalPlan = functions
//   .region('us-central1')
//   .runWith({
//     platform: 'gcfv2',
//     timeoutSeconds: 540, // 9 minutes (maximum timeout)
//     memory: '1GB' // Increase memory allocation
//   })
//   .pubsub
//   .schedule('12 19 * * 5')
//   .timeZone('America/Los_Angeles')
//   .onRun(async () => analyzeResponsesAndSendFinalPlan());

// Keep the manual function for testing
exports.sendMessagesToSubscribers = sendMessagesToSubscribers;

// Manual function for testing the new flexible system
exports.testAnalyzeAndSendMessages = analyzeChatsAndDecideMessages;
