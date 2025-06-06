const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');
const prompts = require('./prompts');

const DEBUG_PAUSE_IMAGE_GEN = true; // Set to false to enable DALL·E image generation

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

      // Check if this chatbot should send availability messages now
      if (chatbot.schedules && chatbot.schedules.availabilityMessageSchedule) {
        const schedule = chatbot.schedules.availabilityMessageSchedule;
        
        // Create a date object representing the current time in the chatbot's timezone
        const nowInTimezone = new Date().toLocaleString('en-US', {
          timeZone: schedule.timeZone
        });
        const timezoneDate = new Date(nowInTimezone);
        
        // Get the current day, hour, and minute in the timezone
        const currentDay = timezoneDate.getDay(); // 0 = Sunday, 1 = Monday, etc.
        const currentHour = timezoneDate.getHours();
        const currentMinute = timezoneDate.getMinutes();
        
        // Format current date as YYYY-MM-DD for comparison
        const currentDateString = timezoneDate.toISOString().split('T')[0];
        
        console.log(`Chatbot ${chatbot.name} - Current time in ${schedule.timeZone}: ${currentDateString} ${currentHour}:${String(currentMinute).padStart(2, '0')}`);
        
        let shouldRun = false;
        let executionKey = '';
        
        // Check if we should run based on specific date or day of week
        if (schedule.specificDate) {
          console.log(`Schedule: Specific date ${schedule.specificDate}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
          
          // Check if current date matches specific date and time
          const isScheduledDate = currentDateString === schedule.specificDate;
          const isScheduledHour = currentHour === schedule.hour;
          const isScheduledMinute = currentMinute === schedule.minute;
          
          shouldRun = isScheduledDate && isScheduledHour && isScheduledMinute;
          executionKey = `${chatbot.id}_availability_${schedule.specificDate}`;
          
          if (!shouldRun) {
            console.log(`Skipping chatbot ${chatbot.name} - not scheduled for availability messages now (Date: ${currentDateString}/${schedule.specificDate}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
          }
        } else if (schedule.dayOfWeek !== undefined && schedule.dayOfWeek !== null) {
          console.log(`Schedule: Day ${schedule.dayOfWeek}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
          
          // Legacy day-of-week scheduling
          const isScheduledDay = currentDay === schedule.dayOfWeek;
          const isScheduledHour = currentHour === schedule.hour;
          const isScheduledMinute = currentMinute === schedule.minute;
          
          shouldRun = isScheduledDay && isScheduledHour && isScheduledMinute;
          executionKey = `${chatbot.id}_availability_${currentDateString}`;
          
          if (!shouldRun) {
            console.log(`Skipping chatbot ${chatbot.name} - not scheduled for availability messages now (Day: ${currentDay}/${schedule.dayOfWeek}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
          }
        } else {
          console.log(`Skipping chatbot ${chatbot.name} - no valid schedule configuration`);
          continue;
        }
        
        if (!shouldRun) {
          continue;
        }
        
        // Check if we've already executed this function for this chatbot today
        const executionRef = db.collection('function_executions').doc(executionKey);
        const executionDoc = await executionRef.get();
        
        if (executionDoc.exists) {
          console.log(`Skipping chatbot ${chatbot.name} - availability function already executed for this date`);
          continue;
        }
        
        console.log(`Processing chatbot ${chatbot.name} - scheduled for availability messages now`);
        
        // Mark this execution as completed
        await executionRef.set({
          chatbotId: chatbot.id,
          functionType: 'availability',
          executedAt: admin.firestore.Timestamp.now(),
          date: schedule.specificDate || currentDateString
        });
      } else {
        console.log(`Skipping chatbot ${chatbot.name} - no availability schedule configured`);
        continue;
      }

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
          // Always use chatbot.planningStartDate and chatbot.planningEndDate for dateRangeText
          const startDate = new Date(chatbot.planningStartDate.seconds * 1000);
          const endDate = new Date(chatbot.planningEndDate.seconds * 1000);
          const startDateString = startDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
          const endDateString = endDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
          const dateRangeText = `${startDateString} to ${endDateString}`;

          // Use prompt module for availability message
          const { system, user } = prompts.getAvailabilityPrompt(firstName, dateRangeText);
          // Log the prompt being sent to OpenAI
          console.log('=== AVAILABILITY MESSAGE OPENAI PROMPT DEBUG ===');
          console.log('System Message:', system);
          console.log('User Message:', user);
          console.log('=== END AVAILABILITY PROMPT DEBUG ===');

          // Build the OpenAI payload
          const openaiPayload = {
            model: "gpt-4",
            messages: [
              {
                role: "system",
                content: system
              },
              {
                role: "user",
                content: user
              }
            ],
            temperature: 0.8
          };
          // Log the full payload
          console.log('=== AVAILABILITY MESSAGE OPENAI FULL PAYLOAD ===');
          console.log(JSON.stringify(openaiPayload, null, 2));
          console.log('=== END AVAILABILITY PAYLOAD ===');

          const completion = await openai.chat.completions.create(openaiPayload);

          // Log the full completion object
          console.log('=== AVAILABILITY MESSAGE OPENAI FULL COMPLETION ===');
          console.log(JSON.stringify(completion, null, 2));
          console.log('=== END AVAILABILITY COMPLETION ===');

          aiMessage = completion.choices[0].message.content.trim();
          
          // Log the response received from OpenAI
          console.log('=== AVAILABILITY MESSAGE OPENAI RESPONSE DEBUG ===');
          console.log('Full OpenAI Response:', aiMessage);
          console.log('Response Length:', aiMessage.length);
          console.log('=== END AVAILABILITY RESPONSE DEBUG ===');
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

async function checkUserAvailability(messages, dateRangeText = "the planned dates") {
  try {
    const formattedMessages = messages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');
    
    const completion = await openai.chat.completions.create({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: "You analyze conversations and determine if a user has indicated they are not available for the planned hangout dates. Return ONLY 'available' or 'not available' based on your analysis."
        },
        {
          role: "user",
          content: `Conversation history:\n${formattedMessages}\n\nBased on this conversation, has the user clearly indicated they are NOT available for ${dateRangeText}?`
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
  if (DEBUG_PAUSE_IMAGE_GEN) {
    console.log('DEBUG: Image generation is paused. Returning fallback image.');
    return getFallbackImageForActivity(activity);
  }
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
      
      // Guard against missing date fields
      if (!chatbot.planningStartDate || !chatbot.planningEndDate) {
        console.error(`Chatbot ${chatbot.name} (${chatbot.id}) is missing planningStartDate or planningEndDate. Skipping.`);
        continue;
      }

      // Always define date range variables at the top of the loop
      const startDate = new Date(chatbot.planningStartDate.seconds * 1000);
      const endDate = new Date(chatbot.planningEndDate.seconds * 1000);
      const startDateString = startDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
      const endDateString = endDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
      const startDateFormatted = startDate.toISOString().split('T')[0];
      const endDateFormatted = endDate.toISOString().split('T')[0];
      const dateRangeText = `${startDateString} to ${endDateString}`;
      const dateContext = `\n\nPlanning Date Range: ${startDateString} to ${endDateString}\nDate Format Instructions:\n- Use dates between ${startDateFormatted} and ${endDateFormatted} (YYYY-MM-DD format)\n- Distribute suggestions across the available dates in this range\n- Consider different days within the range for variety`;
      
      // Check if this chatbot should send suggestions now
      if (chatbot.schedules && chatbot.schedules.suggestionsSchedule) {
        const schedule = chatbot.schedules.suggestionsSchedule;
        
        // Create a date object representing the current time in the chatbot's timezone
        const nowInTimezone = new Date().toLocaleString('en-US', {
          timeZone: schedule.timeZone
        });
        const timezoneDate = new Date(nowInTimezone);
        
        // Get the current day, hour, and minute in the timezone
        const currentDay = timezoneDate.getDay(); // 0 = Sunday, 1 = Monday, etc.
        const currentHour = timezoneDate.getHours();
        const currentMinute = timezoneDate.getMinutes();
        
        // Format current date as YYYY-MM-DD for comparison
        const currentDateString = timezoneDate.toISOString().split('T')[0];
        
        console.log(`Chatbot ${chatbot.name} - Current time in ${schedule.timeZone}: ${currentDateString} ${currentHour}:${String(currentMinute).padStart(2, '0')}`);
        
        let shouldRun = false;
        let executionKey = '';
        
        // Check if we should run based on specific date or day of week
        if (schedule.specificDate) {
          console.log(`Schedule: Specific date ${schedule.specificDate}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
          
          // Check if current date matches specific date and time
          const isScheduledDate = currentDateString === schedule.specificDate;
          const isScheduledHour = currentHour === schedule.hour;
          const isScheduledMinute = currentMinute === schedule.minute;
          
          shouldRun = isScheduledDate && isScheduledHour && isScheduledMinute;
          executionKey = `${chatbot.id}_suggestions_${schedule.specificDate}`;
          
          if (!shouldRun) {
            console.log(`Skipping chatbot ${chatbot.name} - not scheduled for suggestions now (Date: ${currentDateString}/${schedule.specificDate}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
          }
        } else if (schedule.dayOfWeek !== undefined && schedule.dayOfWeek !== null) {
          console.log(`Schedule: Day ${schedule.dayOfWeek}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
          
          // Legacy day-of-week scheduling
          const isScheduledDay = currentDay === schedule.dayOfWeek;
          const isScheduledHour = currentHour === schedule.hour;
          const isScheduledMinute = currentMinute === schedule.minute;
          
          shouldRun = isScheduledDay && isScheduledHour && isScheduledMinute;
          executionKey = `${chatbot.id}_suggestions_${currentDateString}`;
          
          if (!shouldRun) {
            console.log(`Skipping chatbot ${chatbot.name} - not scheduled for suggestions now (Day: ${currentDay}/${schedule.dayOfWeek}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
          }
        } else {
          console.log(`Skipping chatbot ${chatbot.name} - no valid suggestions schedule configuration`);
          continue;
        }
        
        if (!shouldRun) {
          continue;
        }
        
        // Check if we've already executed this function for this chatbot today
        const executionRef = db.collection('function_executions').doc(executionKey);
        const executionDoc = await executionRef.get();
        
        if (executionDoc.exists) {
          console.log(`Skipping chatbot ${chatbot.name} - suggestions function already executed for this date`);
          continue;
        }
        
        console.log(`Processing chatbot ${chatbot.name} - scheduled for suggestions now`);
        
        // Mark this execution as completed
        await executionRef.set({
          chatbotId: chatbot.id,
          functionType: 'suggestions',
          executedAt: admin.firestore.Timestamp.now(),
          date: schedule.specificDate || currentDateString
        });
      } else {
        console.log(`Skipping chatbot ${chatbot.name} - no suggestions schedule configured`);
        continue;
      }

      console.log(`Fetching chats for chatbot: ${chatbot.id}`);
      const chatsSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbot.id)
        .get();
      console.log(`Found ${chatsSnapshot.size} chats for chatbot: ${chatbot.id}`);

      let allMessages = [];
      let unavailableUserIds = [];
      let availableUserCities = [];
      
      // First pass to identify which users are unavailable and collect home cities
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
          const isUnavailable = await checkUserAvailability(messages, dateRangeText);
          if (isUnavailable) {
            unavailableUserIds.push(userId);
            console.log(`User ${userId} indicated they are not available`);
          } else {
            console.log(`User ${userId} appears to be available, adding their messages`);
            allMessages = allMessages.concat(messages);
            
            // Get user's home city for available users
            try {
              const userDoc = await db.collection('users').doc(userId).get();
              const user = userDoc.data();
              if (user.homeCity && user.homeCity.trim() !== '') {
                availableUserCities.push(user.homeCity);
                console.log(`Added home city for available user ${userId}: ${user.homeCity}`);
              }
            } catch (error) {
              console.error(`Error fetching user data for ${userId}:`, error);
            }
          }
        } catch (error) {
          console.error(`Error checking availability for user ${userId}:`, error);
          // Default to keeping the user's messages
          allMessages = allMessages.concat(messages);
        }
      }

      console.log(`Total message count for analysis: ${allMessages.length}`);
      console.log(`Unavailable users: ${unavailableUserIds.length}`);
      console.log(`Available user cities: ${availableUserCities.join(', ')}`);
      
      if (allMessages.length === 0) {
        console.log('No messages to analyze, skipping suggestion generation');
        continue;
      }
      
      const formattedMessages = allMessages.map(msg => `${msg.side === 'bot' ? 'Agent' : 'User'}: ${msg.text}`).join('\n');
      let promptMessages = formattedMessages;
      if (formattedMessages.length > 15000) {
        console.log('Warning: Conversation history is very long, truncating to avoid token limits');
        promptMessages = formattedMessages.substring(0, 15000);
        console.log('Truncated message length:', promptMessages.length);
      }

      // Prepare location context for the prompt
      let locationContext = '';
      if (availableUserCities.length > 0) {
        const uniqueCities = [...new Set(availableUserCities)]; // Remove duplicates
        locationContext = `\n\nSubscriber locations: The group members are located in/around: ${uniqueCities.join(', ')}. Please suggest activities in or near these areas.`;
        console.log(`Location context for OpenAI: ${locationContext}`);
      }

      console.log('Calling OpenAI to generate suggestions');
      try {
        // Use prompt module for group suggestion prompt
        const { system, user } = prompts.getSuggestionPrompt(
          promptMessages,
          availableUserCities,
          dateRangeText,
          dateContext
        );
        // Log the prompt being sent to OpenAI
        console.log('=== OPENAI PROMPT DEBUG ===');
        console.log('System Message:', system);
        console.log('User Message:', user);
        console.log('Prompt length:', user.length);
        console.log('=== END PROMPT DEBUG ===');

        // Build the OpenAI payload
        const openaiPayload = {
          model: "gpt-4",
          messages: [
            {
              role: "system",
              content: system
            },
            {
              role: "user",
              content: user
            }
          ],
          temperature: 0.8
        };
        // Log the full payload
        console.log('=== SUGGESTION GENERATION OPENAI FULL PAYLOAD ===');
        console.log(JSON.stringify(openaiPayload, null, 2));
        console.log('=== END SUGGESTION PAYLOAD ===');

        // Add timeoutPromise for OpenAI call
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('OpenAI API call timed out')), 30000)
        );

        const openAIPromise = openai.chat.completions.create(openaiPayload);
        // Race the OpenAI call against the timeout
        const completion = await Promise.race([openAIPromise, timeoutPromise]);

        // Log the full completion object
        console.log('=== SUGGESTION GENERATION OPENAI FULL COMPLETION ===');
        console.log(JSON.stringify(completion, null, 2));
        console.log('=== END SUGGESTION COMPLETION ===');

        console.log('Successfully received suggestions from OpenAI');
        const suggestionsText = completion.choices[0].message.content.trim();
        
        // Log the response received from OpenAI
        console.log('=== OPENAI RESPONSE DEBUG ===');
        console.log('Full OpenAI Response:', suggestionsText);
        console.log('Response Length:', suggestionsText.length);
        console.log('=== END RESPONSE DEBUG ===');
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
              text: `Hey ${user.fullname.split(' ')[0]}! Based on our chat, here are some outing ideas for ${dateRangeText}:`,
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
              lastMessage: `${eventCards.length} suggestions for ${dateRangeText}`,
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
    console.log(`Processing chatbot: ${chatbot.name} (${chatbot.id})`);
    
    // Check if this chatbot should send final plan now
    if (chatbot.schedules && chatbot.schedules.finalPlanSchedule) {
      const schedule = chatbot.schedules.finalPlanSchedule;
      
      // Create a date object representing the current time in the chatbot's timezone
      const nowInTimezone = new Date().toLocaleString('en-US', {
        timeZone: schedule.timeZone
      });
      const timezoneDate = new Date(nowInTimezone);
      
      // Get the current day, hour, and minute in the timezone
      const currentDay = timezoneDate.getDay(); // 0 = Sunday, 1 = Monday, etc.
      const currentHour = timezoneDate.getHours();
      const currentMinute = timezoneDate.getMinutes();
      
      // Format current date as YYYY-MM-DD for comparison
      const currentDateString = timezoneDate.toISOString().split('T')[0];
      
      console.log(`Chatbot ${chatbot.name} - Current time in ${schedule.timeZone}: ${currentDateString} ${currentHour}:${String(currentMinute).padStart(2, '0')}`);
      
      let shouldRun = false;
      let executionKey = '';
      
      // Check if we should run based on specific date or day of week
      if (schedule.specificDate) {
        console.log(`Schedule: Specific date ${schedule.specificDate}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
        
        // Check if current date matches specific date and time
        const isScheduledDate = currentDateString === schedule.specificDate;
        const isScheduledHour = currentHour === schedule.hour;
        const isScheduledMinute = currentMinute === schedule.minute;
        
        shouldRun = isScheduledDate && isScheduledHour && isScheduledMinute;
        executionKey = `${chatbot.id}_finalplan_${schedule.specificDate}`;
        
        if (!shouldRun) {
          console.log(`Skipping chatbot ${chatbot.name} - not scheduled for final plan now (Date: ${currentDateString}/${schedule.specificDate}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
        }
      } else if (schedule.dayOfWeek !== undefined && schedule.dayOfWeek !== null) {
        console.log(`Schedule: Day ${schedule.dayOfWeek}, ${schedule.hour}:${String(schedule.minute).padStart(2, '0')}`);
        
        // Legacy day-of-week scheduling
        const isScheduledDay = currentDay === schedule.dayOfWeek;
        const isScheduledHour = currentHour === schedule.hour;
        const isScheduledMinute = currentMinute === schedule.minute;
        
        shouldRun = isScheduledDay && isScheduledHour && isScheduledMinute;
        executionKey = `${chatbot.id}_finalplan_${currentDateString}`;
        
        if (!shouldRun) {
          console.log(`Skipping chatbot ${chatbot.name} - not scheduled for final plan now (Day: ${currentDay}/${schedule.dayOfWeek}, Time: ${currentHour}:${currentMinute}/${schedule.hour}:${schedule.minute})`);
        }
      } else {
        console.log(`Skipping chatbot ${chatbot.name} - no valid final plan schedule configuration`);
        continue;
      }
      
      if (!shouldRun) {
        continue;
      }
      
      // Check if we've already executed this function for this chatbot today
      const executionRef = db.collection('function_executions').doc(executionKey);
      const executionDoc = await executionRef.get();
      
      if (executionDoc.exists) {
        console.log(`Skipping chatbot ${chatbot.name} - final plan function already executed for this date`);
        continue;
      }
      
      console.log(`Processing chatbot ${chatbot.name} - scheduled for final plan now`);
      
      // Mark this execution as completed
      await executionRef.set({
        chatbotId: chatbot.id,
        functionType: 'finalplan',
        executedAt: admin.firestore.Timestamp.now(),
        date: schedule.specificDate || currentDateString
      });
    } else {
      console.log(`Skipping chatbot ${chatbot.name} - no final plan schedule configured`);
      continue;
    }

    const chatsSnapshot = await db.collection('chats')
      .where('chatbotId', '==', chatbot.id)
      .get();

    let allMessages = [];
    let unavailableUserIds = [];
    let availableUserNames = [];
    let availableUserIds = [];
    let originalSuggestions = [];
    
    // Format date range for availability checking
    let dateRangeText = "the upcoming weekend";
    if (chatbot.planningStartDate && chatbot.planningEndDate) {
      const startDate = new Date(chatbot.planningStartDate.seconds * 1000);
      const endDate = new Date(chatbot.planningEndDate.seconds * 1000);
      const startDateString = startDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
      const endDateString = endDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
      
      if (startDate.getFullYear() !== endDate.getFullYear()) {
        const startWithYear = startDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
        const endWithYear = endDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
        dateRangeText = `${startWithYear} to ${endWithYear}`;
      } else {
        dateRangeText = `${startDateString} to ${endDateString}`;
      }
    }
    
    // First pass to identify which users are unavailable and collect names of available users
    for (const chatDoc of chatsSnapshot.docs) {
      const userId = chatDoc.data().userId;
      const messagesSnapshot = await chatDoc.ref.collection('messages')
        .orderBy('timestamp', 'asc')
        .get();

      const messages = messagesSnapshot.docs.map(doc => doc.data());
      
      // Check if user is available based on their messages
      const isUnavailable = await checkUserAvailability(messages, dateRangeText);
      
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

    // Use prompt module for final plan selection
    const { system, user } = prompts.getFinalPlanPrompt(
      formattedMessages,
      availableUserNames,
      dateRangeText,
      formattedSuggestions
    );
    // Log the prompt being sent to OpenAI
    console.log('=== FINAL PLAN SELECTION OPENAI PROMPT DEBUG ===');
    console.log('System Message:', system);
    console.log('User Message:', user);
    console.log('=== END FINAL PLAN PROMPT DEBUG ===');

    // Build the OpenAI payload
    const openaiPayload = {
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content: system
        },
        {
          role: "user",
          content: user
        }
      ],
      temperature: 0.3
    };
    // Log the full payload
    console.log('=== FINAL PLAN SELECTION OPENAI FULL PAYLOAD ===');
    console.log(JSON.stringify(openaiPayload, null, 2));
    console.log('=== END FINAL PLAN PAYLOAD ===');

    const completion = await openai.chat.completions.create(openaiPayload);

    // Log the full completion object
    console.log('=== FINAL PLAN SELECTION OPENAI FULL COMPLETION ===');
    console.log(JSON.stringify(completion, null, 2));
    console.log('=== END FINAL PLAN COMPLETION ===');

    const rawResponse = completion.choices[0].message.content.trim();
    // Log the response received from OpenAI
    console.log('=== FINAL PLAN SELECTION OPENAI RESPONSE DEBUG ===');
    console.log('Full OpenAI Response:', rawResponse);
    console.log('Response Length:', rawResponse.length);
    console.log('=== END FINAL PLAN RESPONSE DEBUG ===');

    let selectedIndex = parseInt(rawResponse) - 1;
    
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
  .schedule('* * * * *') // Run every minute to check individual chatbot schedules
  .timeZone('UTC')
  .onRun(async () => sendMessagesToSubscribers());

exports.suggestWeekendOutings = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540, // 9 minutes (maximum timeout)
    memory: '1GB' // Increase memory allocation
  })
  .pubsub
  .schedule('* * * * *') // Run every minute to check individual chatbot schedules
  .timeZone('UTC')
  .onRun(async () => analyzeChatsAndSuggestOutings());

exports.sendFinalPlan = functions
  .region('us-central1')
  .runWith({
    platform: 'gcfv2',
    timeoutSeconds: 540, // 9 minutes (maximum timeout)
    memory: '1GB' // Increase memory allocation
  })
  .pubsub
  .schedule('* * * * *') // Run every minute to check individual chatbot schedules
  .timeZone('UTC')
  .onRun(async () => analyzeResponsesAndSendFinalPlan());

exports.sendMessagesToSubscribers = sendMessagesToSubscribers;
