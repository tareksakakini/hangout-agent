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

async function analyzeChatsAndSuggestOutings() {
  console.log('Starting analyzeChatsAndSuggestOutings function');
  const db = admin.firestore();
  
  try {
    console.log('Fetching chatbots');
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`Found ${chatbotsSnapshot.size} chatbots`);

    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbot = chatbotDoc.data();
      console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
      
      console.log(`Fetching chats for chatbot: ${chatbot.id}`);
      const chatsSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbot.id)
        .get();
      console.log(`Found ${chatsSnapshot.size} chats for chatbot: ${chatbot.id}`);

      let allMessages = [];
      let unavailableUserIds = [];
      
      // First pass to identify which users are unavailable
      console.log('Starting to process individual chats and check user availability');
      for (const chatDoc of chatsSnapshot.docs) {
        const userId = chatDoc.data().userId;
        console.log(`Processing chat with userId: ${userId}`);
        
        console.log(`Fetching messages for chat: ${chatDoc.id}`);
        const messagesSnapshot = await chatDoc.ref.collection('messages')
          .orderBy('timestamp', 'asc')
          .get();
        console.log(`Found ${messagesSnapshot.size} messages for chat: ${chatDoc.id}`);

        const messages = messagesSnapshot.docs.map(doc => doc.data());
        
        // Check if user is available based on their messages
        console.log(`Checking availability for user: ${userId}`);
        try {
          const isUnavailable = await checkUserAvailability(messages);
          if (isUnavailable) {
            unavailableUserIds.push(userId);
            console.log(`User ${userId} indicated they are not available`);
          } else {
            console.log(`User ${userId} appears to be available, adding their messages`);
            allMessages = allMessages.concat(messages);
          }
        } catch (error) {
          console.error(`Error checking availability for user ${userId}:`, error);
          // Default to keeping the user's messages
          allMessages = allMessages.concat(messages);
        }
      }

      console.log(`Total message count for analysis: ${allMessages.length}`);
      console.log(`Unavailable users: ${unavailableUserIds.length}`);
      
      if (allMessages.length === 0) {
        console.log('No messages to analyze, skipping suggestion generation');
        continue;
      }
      
      const formattedMessages = allMessages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');
      console.log('Formatted messages for OpenAI, length:', formattedMessages.length);
      
      if (formattedMessages.length > 30000) {
        console.log('Warning: Conversation history is very long, truncating to avoid token limits');
        const truncatedMessages = formattedMessages.substring(0, 30000);
        console.log('Truncated message length:', truncatedMessages.length);
      }

      console.log('Calling OpenAI to generate suggestions');
      try {
        // Set a timeout for the OpenAI call (30 seconds)
        const timeoutPromise = new Promise((_, reject) => 
          setTimeout(() => reject(new Error('OpenAI API call timed out')), 30000)
        );
        
        const openAIPromise = openai.chat.completions.create({
          model: "gpt-4",
          messages: [
            {
              role: "system",
              content: "You are a helpful assistant that analyzes group chat conversations and suggests weekend outing options. For each suggestion, include activity, specific location with address, date (next weekend), specific start and end times."
            },
            {
              role: "user",
              content: `Conversation history:\n${formattedMessages.length > 30000 ? formattedMessages.substring(0, 30000) : formattedMessages}\n\nBased on this, suggest 5 outing options. Format each suggestion as a separate paragraph with these details clearly labeled: Activity, Location (with address), Date, Start Time, End Time. Add a brief 1-2 sentence description about why this would be fun.`
            }
          ],
          temperature: 0.8
        });
        
        // Race the OpenAI call against the timeout
        const completion = await Promise.race([openAIPromise, timeoutPromise]);

        console.log('Successfully received suggestions from OpenAI');
        const suggestionsText = completion.choices[0].message.content.trim();
        console.log('Suggestions text length:', suggestionsText.length);
        const suggestionParagraphs = suggestionsText.split(/\n\n+/);
        console.log(`Split into ${suggestionParagraphs.length} suggestion paragraphs`);
        
        // Parse each suggestion and create event cards
        const eventCards = [];
        for (let i = 0; i < suggestionParagraphs.length; i++) {
          const paragraph = suggestionParagraphs[i];
          if (paragraph.trim().length > 0) {
            console.log(`Processing suggestion paragraph ${i+1}, length: ${paragraph.length}`);
            try {
              console.log('Parsing event details');
              const eventData = await parseEventDetails(paragraph);
              console.log('Getting image for activity:', eventData.activity);
              const eventCard = await createEventCard(eventData);
              eventCards.push(eventCard);
              console.log(`Successfully created card for: ${eventData.activity}`);
            } catch (error) {
              console.error(`Error processing suggestion ${i+1}:`, error);
            }
          }
        }
        console.log(`Created ${eventCards.length} event cards`);

        // Only send to users who are available
        console.log('Sending suggestions to available users');
        for (const chatDoc of chatsSnapshot.docs) {
          const userId = chatDoc.data().userId;
          
          // Skip users who indicated they are not available
          if (unavailableUserIds.includes(userId)) {
            console.log(`Skipping suggestions for unavailable user ${userId}`);
            continue;
          }
          
          try {
            console.log(`Fetching user data for ${userId}`);
            const userDoc = await db.collection('users').doc(userId).get();
            const user = userDoc.data();
            
            // Create an intro message
            console.log(`Sending intro message to ${user.fullname}`);
            const introMessage = {
              id: admin.firestore.Timestamp.now().toMillis().toString(),
              text: `Hey ${user.fullname.split(' ')[0]}! Based on our chat, here are some outing ideas for the weekend:`,
              senderId: chatbot.id,
              timestamp: admin.firestore.Timestamp.now(),
              side: 'bot'
            };
            await db.collection('chats').doc(chatDoc.id).collection('messages').add(introMessage);
            
            // Add each event card as a separate message
            console.log(`Sending ${eventCards.length} event cards to ${user.fullname}`);
            for (const eventCard of eventCards) {
              const cardMessage = {
                id: admin.firestore.Timestamp.now().toMillis().toString(),
                eventCard: eventCard,
                senderId: chatbot.id,
                timestamp: admin.firestore.Timestamp.now(),
                side: 'bot'
              };
              await db.collection('chats').doc(chatDoc.id).collection('messages').add(cardMessage);
            }
            
            // Update the chat's last message
            console.log(`Updating last message for chat ${chatDoc.id}`);
            await chatDoc.ref.update({
              lastMessage: `${eventCards.length} weekend suggestions`,
              updatedAt: admin.firestore.Timestamp.now()
            });
            console.log(`Successfully sent suggestions to ${user.fullname}`);
          } catch (error) {
            console.error(`Error sending suggestions to user ${userId}:`, error);
          }
        }
      } catch (error) {
        console.error('Error generating suggestions with OpenAI:', error);
        console.error('Error details:', JSON.stringify(error));
      }
    }
    console.log('analyzeChatsAndSuggestOutings completed successfully');
  } catch (error) {
    console.error('Error in analyzeChatsAndSuggestOutings:', error);
    console.error('Error stack:', error.stack);
    throw error;
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
    let availableUserIds = [];
    let originalSuggestions = [];
    
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
        availableUserIds.push(userId);
        allMessages = allMessages.concat(messages);
        
        // Collect original suggestions from event cards
        messages.forEach(msg => {
          if (msg.eventCard && !originalSuggestions.some(s => s.activity === msg.eventCard.activity)) {
            originalSuggestions.push(msg.eventCard);
          }
        });
      }
    }

    // If no suggestions were found or no available users, skip this chatbot
    if (originalSuggestions.length === 0 || availableUserIds.length === 0) {
      console.log('No original suggestions found or no available users, skipping final plan generation');
      continue;
    }

    const formattedMessages = allMessages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');
    
    // Format suggestions with their index numbers for reference
    const formattedSuggestions = originalSuggestions.map((s, index) => 
      `Option ${index + 1}:\nActivity: ${s.activity}\nLocation: ${s.location}\nDate: ${s.date}\nTime: ${s.startTime}-${s.endTime}\nDescription: ${s.description}`
    ).join('\n\n');

    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "You analyze group chat conversations to select the most popular weekend plan from the original suggestions. You must choose exactly one of the numbered options provided. Look for explicit preferences (e.g., 'I like option 1' or 'the first one sounds good') and implicit preferences in the conversation."
        },
        {
          role: "user",
          content: `Conversation history:\n${formattedMessages}\n\nAvailable participants: ${availableUserNames.join(', ')}\n\nOriginal suggestions (numbered for reference):\n${formattedSuggestions}\n\nBased on the conversation, which option (1-${originalSuggestions.length}) is most preferred by the group? Return ONLY the number of your selection (e.g., '1' or '2').`
        }
      ],
      temperature: 0.3
    });

    const selectedIndex = parseInt(completion.choices[0].message.content.trim()) - 1;
    
    // Validate the selection
    if (isNaN(selectedIndex) || selectedIndex < 0 || selectedIndex >= originalSuggestions.length) {
      console.error('Invalid selection from AI, defaulting to first suggestion');
      selectedIndex = 0;
    }

    // Use the selected suggestion as the final plan
    const finalEventCard = originalSuggestions[selectedIndex];
    finalEventCard.attendees = availableUserNames;

    // Create a group for the attendees
    const groupId = `group_${chatbot.id}_${admin.firestore.Timestamp.now().toMillis()}`;
    const groupName = `${finalEventCard.activity} Group`;
    
    try {
      await db.collection('groups').doc(groupId).set({
        id: groupId,
        name: groupName,
        participants: availableUserIds,
        participantNames: availableUserNames,
        createdAt: admin.firestore.Timestamp.now(),
        eventDetails: finalEventCard,
        lastMessage: null,
        updatedAt: admin.firestore.Timestamp.now()
      });
      
      console.log(`Created group ${groupId} for event: ${finalEventCard.activity}`);
      
      // Send a welcome message to the group
      const welcomeMessage = {
        id: admin.firestore.Timestamp.now().toMillis().toString(),
        text: `Welcome to the ${finalEventCard.activity} group! Use this chat to coordinate and discuss the event details.`,
        senderId: 'system',
        senderName: 'System',
        timestamp: admin.firestore.Timestamp.now()
      };
      
      await db.collection('groups').doc(groupId).collection('messages').add(welcomeMessage);
      
      // Update the group's last message
      await db.collection('groups').doc(groupId).update({
        lastMessage: welcomeMessage.text,
        updatedAt: admin.firestore.Timestamp.now()
      });
      
    } catch (error) {
      console.error('Error creating group:', error);
    }

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

      // Send an intro message
      const introMessage = {
        id: admin.firestore.Timestamp.now().toMillis().toString(),
        text: `Hey ${user.fullname.split(' ')[0]}! Based on everyone's preferences, here's the plan we're going with. A group chat has been created for everyone attending to coordinate!`,
        senderId: chatbot.id,
        timestamp: admin.firestore.Timestamp.now(),
        side: 'bot'
      };
      await db.collection('chats').doc(chatDoc.id).collection('messages').add(introMessage);
      
      // Send the event card
      const cardMessage = {
        id: admin.firestore.Timestamp.now().toMillis().toString(),
        eventCard: finalEventCard,
        senderId: chatbot.id,
        timestamp: admin.firestore.Timestamp.now(),
        side: 'bot'
      };
      await db.collection('chats').doc(chatDoc.id).collection('messages').add(cardMessage);
      
      // Update the chat's last message
      await chatDoc.ref.update({
        lastMessage: `Final plan: ${finalEventCard.activity}`,
        updatedAt: admin.firestore.Timestamp.now()
      });
    }
  }
}

exports.sendWeeklyMessages = functions
  .region('us-central1')
  .runWith({ platform: 'gcfv2' })
  .pubsub
  .schedule('08 15 * * 5')
  .timeZone('America/Los_Angeles')
  .onRun(async () => sendMessagesToSubscribers());

exports.suggestWeekendOutings = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540, // 9 minutes (maximum timeout)
    memory: '1GB' // Increase memory allocation
  })
  .pubsub
  .schedule('11 15 * * 5')
  .timeZone('America/Los_Angeles')
  .onRun(async () => analyzeChatsAndSuggestOutings());

exports.sendFinalPlan = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540, // 9 minutes (maximum timeout)
    memory: '1GB' // Increase memory allocation
  })
  .pubsub
  .schedule('14 15 * * 5')
  .timeZone('America/Los_Angeles')
  .onRun(async () => analyzeResponsesAndSendFinalPlan());

exports.sendMessagesToSubscribers = sendMessagesToSubscribers;
