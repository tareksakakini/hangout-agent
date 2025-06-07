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

// Scheduled function to send suggestions
exports.sendSuggestions = functions.pubsub.schedule('*/5 * * * *').onRun(async (context) => {
  const now = new Date();
  console.log(`🕐 Checking for chatbots ready to send suggestions at: ${now.toISOString()}`);
  console.log(`📅 Current time breakdown - Year: ${now.getFullYear()}, Month: ${now.getMonth()}, Date: ${now.getDate()}, Hour: ${now.getHours()}, Minute: ${now.getMinutes()}, Day: ${now.getDay()}`);
  
  try {
    const chatbotsSnapshot = await db.collection('chatbots').get();
    console.log(`🔍 Found ${chatbotsSnapshot.docs.length} total chatbots to check`);
    
    for (const chatbotDoc of chatbotsSnapshot.docs) {
      const chatbotData = chatbotDoc.data();
      const chatbotId = chatbotData.id;
      const chatbotName = chatbotData.name;
      const schedules = chatbotData.schedules;
      
      console.log(`\n🤖 Checking chatbot: "${chatbotName}" (ID: ${chatbotId})`);
      
      if (!schedules) {
        console.log(`❌ No schedules found for chatbot: ${chatbotName}`);
        continue;
      }
      
      if (!schedules.suggestionsSchedule) {
        console.log(`❌ No suggestionsSchedule found for chatbot: ${chatbotName}`);
        continue;
      }
      
      const suggestionsSchedule = schedules.suggestionsSchedule;
      console.log(`📋 Suggestions schedule for ${chatbotName}:`, JSON.stringify(suggestionsSchedule, null, 2));
      
      // Check if it's time to send suggestions
      const shouldSend = await isTimeToSend(suggestionsSchedule, now);
      console.log(`⏰ Time check result for ${chatbotName}: ${shouldSend}`);
      
      if (shouldSend) {
        console.log(`✅ Processing suggestions for chatbot: ${chatbotName}`);
        await processSuggestionsForChatbot(chatbotId, chatbotData);
      }
    }
    
    console.log(`🏁 Finished checking all chatbots`);
  } catch (error) {
    console.error('Error in sendSuggestions function:', error);
  }
});

// Helper function to check if it's time to send
async function isTimeToSend(schedule, now) {
  console.log(`🔍 Checking schedule:`, JSON.stringify(schedule, null, 2));
  console.log(`🕐 Current time (UTC): ${now.toISOString()}`);
  
  const timeZone = schedule.timeZone || 'UTC';
  console.log(`🌍 Using timezone: ${timeZone}`);
  
  // Convert current time to the schedule's timezone
  const nowInTimeZone = new Date(now.toLocaleString("en-US", { timeZone: timeZone }));
  console.log(`🕐 Current time in ${timeZone}: ${nowInTimeZone.toISOString()}`);
  console.log(`🕐 Current time breakdown in ${timeZone} - Year: ${nowInTimeZone.getFullYear()}, Month: ${nowInTimeZone.getMonth()}, Date: ${nowInTimeZone.getDate()}, Hour: ${nowInTimeZone.getHours()}, Minute: ${nowInTimeZone.getMinutes()}, Day: ${nowInTimeZone.getDay()}`);
  
  if (schedule.specificDate) {
    console.log(`📅 Using specific date schedule: ${schedule.specificDate}`);
    
    // Parse the date string and create a Date object in the schedule's timezone
    const [year, month, day] = schedule.specificDate.split('-').map(Number);
    const scheduleDate = new Date();
    scheduleDate.setFullYear(year, month - 1, day); // month is 0-indexed
    scheduleDate.setHours(schedule.hour, schedule.minute, 0, 0);
    
    console.log(`📅 Parsed schedule date: ${scheduleDate.toISOString()}`);
    console.log(`🕐 Schedule time breakdown - Year: ${scheduleDate.getFullYear()}, Month: ${scheduleDate.getMonth()}, Date: ${scheduleDate.getDate()}, Hour: ${scheduleDate.getHours()}, Minute: ${scheduleDate.getMinutes()}`);
    
    const yearMatch = nowInTimeZone.getFullYear() === scheduleDate.getFullYear();
    const monthMatch = nowInTimeZone.getMonth() === scheduleDate.getMonth();
    const dateMatch = nowInTimeZone.getDate() === scheduleDate.getDate();
    const hourMatch = nowInTimeZone.getHours() === scheduleDate.getHours();
    const minuteMatch = nowInTimeZone.getMinutes() === scheduleDate.getMinutes();
    
    console.log(`🔍 Time comparison results (in ${timeZone}):`);
    console.log(`   Year match: ${yearMatch} (${nowInTimeZone.getFullYear()} === ${scheduleDate.getFullYear()})`);
    console.log(`   Month match: ${monthMatch} (${nowInTimeZone.getMonth()} === ${scheduleDate.getMonth()})`);
    console.log(`   Date match: ${dateMatch} (${nowInTimeZone.getDate()} === ${scheduleDate.getDate()})`);
    console.log(`   Hour match: ${hourMatch} (${nowInTimeZone.getHours()} === ${scheduleDate.getHours()})`);
    console.log(`   Minute match: ${minuteMatch} (${nowInTimeZone.getMinutes()} === ${scheduleDate.getMinutes()})`);
    
    const result = yearMatch && monthMatch && dateMatch && hourMatch && minuteMatch;
    console.log(`🎯 Final result for specific date: ${result}`);
    return result;
  }
  
  // For recurring schedules (day of week)
  if (schedule.dayOfWeek !== null && schedule.dayOfWeek !== undefined) {
    console.log(`📅 Using recurring day-of-week schedule: ${schedule.dayOfWeek}`);
    
    const dayMatch = nowInTimeZone.getDay() === schedule.dayOfWeek;
    const hourMatch = nowInTimeZone.getHours() === schedule.hour;
    const minuteMatch = nowInTimeZone.getMinutes() === schedule.minute;
    
    console.log(`🔍 Recurring schedule comparison results (in ${timeZone}):`);
    console.log(`   Day match: ${dayMatch} (${nowInTimeZone.getDay()} === ${schedule.dayOfWeek})`);
    console.log(`   Hour match: ${hourMatch} (${nowInTimeZone.getHours()} === ${schedule.hour})`);
    console.log(`   Minute match: ${minuteMatch} (${nowInTimeZone.getMinutes()} === ${schedule.minute})`);
    
    const result = dayMatch && hourMatch && minuteMatch;
    console.log(`🎯 Final result for recurring schedule: ${result}`);
    return result;
  }
  
  console.log(`❌ No valid schedule type found`);
  return false;
}

// Process suggestions for a specific chatbot
async function processSuggestionsForChatbot(chatbotId, chatbotData) {
  try {
    const chatbotName = chatbotData.name;
    const subscribers = chatbotData.subscribers || [];
    const planningStartDate = chatbotData.planningStartDate;
    const planningEndDate = chatbotData.planningEndDate;
    
    console.log(`🔍 Analyzing chats for chatbot: ${chatbotName}`);
    
    // Fetch all chat histories for this chatbot
    const allChatHistory = await fetchAllChatHistories(chatbotId, subscribers);
    
    // Call OpenAI to identify unavailable users
    console.log('🤖 Identifying unavailable users...');
    const unavailableUsers = await identifyUnavailableUsers(allChatHistory, planningStartDate, planningEndDate);
    
    // Get available users and their details
    const availableUsers = await getAvailableUsersWithDetails(subscribers, unavailableUsers);
    
    if (availableUsers.length === 0) {
      console.log('❌ No available users found for suggestions');
      return;
    }
    
    // Call OpenAI to generate suggestions
    console.log('💡 Generating hangout suggestions...');
    const suggestions = await generateHangoutSuggestions(allChatHistory, availableUsers, planningStartDate, planningEndDate);
    
    // Send suggestions to available users
    console.log(`📤 Sending suggestions to ${availableUsers.length} available users...`);
    await sendSuggestionsToUsers(chatbotId, chatbotName, suggestions, availableUsers);
    
    console.log(`✅ Successfully processed suggestions for ${chatbotName}`);
    
  } catch (error) {
    console.error(`Error processing suggestions for chatbot ${chatbotId}:`, error);
  }
}

// Fetch all chat histories for a chatbot
async function fetchAllChatHistories(chatbotId, subscribers) {
  const allChats = {};
  
  // Get all chats for this chatbot
  const chatsSnapshot = await db.collection('chats').where('chatbotId', '==', chatbotId).get();
  
  for (const chatDoc of chatsSnapshot.docs) {
    const chatData = chatDoc.data();
    const userId = chatData.userId;
    
    // Fetch messages for this chat
    const messagesSnapshot = await db.collection('chats').doc(chatDoc.id).collection('messages')
      .orderBy('timestamp', 'asc').get();
    
    const messages = [];
    messagesSnapshot.docs.forEach(messageDoc => {
      const data = messageDoc.data();
      if (data.timestamp && data.text && data.senderId) {
        messages.push({
          sender: data.senderId,
          text: data.text,
          timestamp: data.timestamp.toDate(),
          side: data.side || 'unknown'
        });
      }
    });
    
    if (messages.length > 0) {
      allChats[userId] = messages;
    }
  }
  
  return allChats;
}

// Use OpenAI to identify users who indicated unavailability
async function identifyUnavailableUsers(chatHistory, planningStartDate, planningEndDate) {
  const dateRange = formatDateRangeForPrompt(planningStartDate, planningEndDate);
  
  const prompt = `
Analyze the following chat conversations to identify users who have clearly indicated they are NOT available for the hangout during ${dateRange}.

Only include users who have explicitly stated unavailability, such as:
- "I can't make it"
- "I'm not available"
- "I have other plans"
- "I'll be traveling"
- Clear schedule conflicts

Do not include users who:
- Haven't responded yet
- Gave vague or uncertain responses
- Only mentioned preferences without indicating unavailability

Chat History:
${JSON.stringify(chatHistory, null, 2)}

Return ONLY a JSON array of user IDs who are unavailable. Example: ["user123", "user456"]
If no users are clearly unavailable, return an empty array: []
`;

  try {
    const completion = await openai.chat.completions.create({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 200,
      temperature: 0.1,
    });

    const response = completion.choices[0]?.message?.content?.trim();
    const unavailableUsers = JSON.parse(response || '[]');
    
    console.log(`🚫 Identified ${unavailableUsers.length} unavailable users:`, unavailableUsers);
    return unavailableUsers;
    
  } catch (error) {
    console.error('Error identifying unavailable users:', error);
    return [];
  }
}

// Get available users with their details
async function getAvailableUsersWithDetails(allSubscribers, unavailableUsers) {
  const availableUsers = [];
  
  console.log(`👥 Processing ${allSubscribers.length} subscribers:`, allSubscribers);
  console.log(`🚫 Unavailable user IDs:`, unavailableUsers);
  
  for (const subscriberId of allSubscribers) {
    // Fetch user details first to get both ID and username
    let userDoc = await db.collection('users').doc(subscriberId).get();
    let userData = userDoc.data();
    let actualUserId = subscriberId;
    
    // If not found by ID, try by username
    if (!userData) {
      const usernameQuery = await db.collection('users').where('username', '==', subscriberId).get();
      if (!usernameQuery.empty) {
        userDoc = usernameQuery.docs[0];
        userData = userDoc.data();
        actualUserId = userDoc.id; // Get the actual user ID
        console.log(`📝 Subscriber "${subscriberId}" resolved to user ID: ${actualUserId}`);
      }
    }
    
    if (!userData) {
      console.log(`❌ Could not find user data for subscriber: ${subscriberId}`);
      continue;
    }
    
    // Check if this user is unavailable (compare against both ID and username)
    const isUnavailable = unavailableUsers.includes(actualUserId) || unavailableUsers.includes(userData.username);
    
    console.log(`🔍 Checking availability for ${userData.fullname} (ID: ${actualUserId}, Username: ${userData.username})`);
    console.log(`   - Unavailable by ID: ${unavailableUsers.includes(actualUserId)}`);
    console.log(`   - Unavailable by username: ${unavailableUsers.includes(userData.username)}`);
    console.log(`   - Final result: ${isUnavailable ? 'UNAVAILABLE' : 'AVAILABLE'}`);
    
    if (isUnavailable) {
      console.log(`🚫 Skipping unavailable user: ${userData.fullname}`);
      continue;
    }
    
    availableUsers.push({
      id: actualUserId,
      name: userData.fullname,
      username: userData.username,
      homeCity: userData.homeCity || 'Unknown'
    });
    
    console.log(`✅ Added available user: ${userData.fullname}`);
  }
  
  console.log(`📊 Final result: ${availableUsers.length} available users out of ${allSubscribers.length} total subscribers`);
  return availableUsers;
}

// Use OpenAI to generate hangout suggestions
async function generateHangoutSuggestions(chatHistory, availableUsers, planningStartDate, planningEndDate) {
  const dateRange = formatDateRangeForPrompt(planningStartDate, planningEndDate);
  const userLocations = availableUsers.map(user => `${user.name} from ${user.homeCity}`).join(', ');
  
  const prompt = `
Based on the chat history and user information, generate 5 specific hangout suggestions for ${dateRange}.

Available Users: ${userLocations}

Chat History (contains preferences and availability info):
${JSON.stringify(chatHistory, null, 2)}

Please consider:
- User preferences mentioned in the chats
- Geographic locations of users
- Time preferences (morning, afternoon, evening)
- Activity types mentioned (indoor/outdoor, active/relaxed, etc.)
- Accessibility for all participants

Generate 5 diverse suggestions with this format:
1. [Activity Name] - [Brief description] (Location: [Suggested area])
2. [Activity Name] - [Brief description] (Location: [Suggested area])
...

Keep each suggestion concise (1-2 sentences) and practical.
`;

  try {
    const completion = await openai.chat.completions.create({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 800,
      temperature: 0.7,
    });

    const suggestions = completion.choices[0]?.message?.content?.trim();
    console.log('💡 Generated suggestions:', suggestions);
    return suggestions;
    
  } catch (error) {
    console.error('Error generating suggestions:', error);
    return 'Unable to generate suggestions at this time. Please share your preferences and I\'ll help coordinate manually!';
  }
}

// Send suggestions to available users
async function sendSuggestionsToUsers(chatbotId, chatbotName, suggestions, availableUsers) {
  for (const user of availableUsers) {
    try {
      // Find the chat for this user
      const chatSnapshot = await db.collection('chats')
        .where('chatbotId', '==', chatbotId)
        .where('userId', '==', user.id)
        .get();
      
      if (chatSnapshot.empty) {
        console.log(`❌ No chat found for user ${user.name}`);
        continue;
      }
      
      const chatId = chatSnapshot.docs[0].id;
      
      const suggestionMessage = `🎉 **Hangout Suggestions!**

Hey ${user.name}! Based on everyone's preferences and availability, here are some great options for our get-together:

${suggestions}

Which of these sounds most interesting to you? Feel free to share your thoughts or suggest modifications! 😊`;

      // Send the message
      const message = {
        id: db.collection('_').doc().id,
        text: suggestionMessage,
        senderId: 'chatbot',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        side: 'bot',
      };
      
      await db.collection('chats').doc(chatId).collection('messages').doc(message.id).set(message);
      console.log(`✅ Sent suggestions to ${user.name}`);
      
    } catch (error) {
      console.error(`Error sending suggestions to ${user.name}:`, error);
    }
  }
}

// Helper function to format date range for prompts
function formatDateRangeForPrompt(startDate, endDate) {
  if (!startDate || !endDate) {
    return 'the upcoming period';
  }
  
  const start = startDate.toDate();
  const end = endDate.toDate();
  
  const formatter = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
  
  const calendar = new Date();
  if (start.toDateString() === end.toDateString()) {
    return formatter.format(start);
  } else {
    return `${formatter.format(start)} through ${formatter.format(end)}`;
  }
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
