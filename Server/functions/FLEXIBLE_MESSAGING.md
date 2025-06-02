# Flexible Messaging System

## Overview

The hangout agent has been upgraded from a rigid scheduled messaging system to a flexible, **message-triggered** system that analyzes chat history and makes intelligent decisions about when and what to message each user **whenever someone in the group sends a message**.

## Key Changes

### Before (Rigid System)
- **3 scheduled functions** running at fixed times every Friday:
  - `sendWeeklyMessages` (6:06 PM) - Initial availability check
  - `suggestWeekendOutings` (6:09 PM) - Activity suggestions  
  - `sendFinalPlan` (6:12 PM) - Final plan and group creation

### After (Flexible System)
- **Message-triggered function** that activates when any subscriber sends a message:
  - `onMessageSent` - Triggers when users send messages, then analyzes chat history and decides what action to take for each user

## How It Works

### 1. Message Trigger
- **Firestore Trigger**: Activates when a new message is added to any chat
- **User Messages Only**: Ignores bot messages to prevent infinite loops
- **Smart Anti-Double-Messaging**: Won't run if the bot was the last to message in that specific chat within 30 minutes
- **Active Hours**: Only runs between 8 AM and 11 PM Pacific Time

### 2. Data Collection
- Collects chat histories for all subscribed users
- Formats conversation context for AI analysis
- Includes user information and message timestamps

### 3. AI Decision Making
The AI agent analyzes each user's conversation and decides:
- **Whether to send a message** or not
- **What type of message** to send:
  - `AVAILABILITY_CHECK`: Ask about weekend availability and preferences
  - `SUGGESTIONS`: Provide specific activity suggestions with event cards
  - `FINAL_PLAN`: Share decided plan and create group chat
  - `FOLLOW_UP`: Ask for more details or clarify preferences
  - `NONE`: Don't send any message

### 4. Message Execution
Based on AI decisions, the system:
- Sends appropriate messages to each user
- Creates event cards for suggestions
- Creates group chats for final plans
- Updates conversation state

## Message Types

### AVAILABILITY_CHECK
Simple text message asking about weekend availability and preferences.

### SUGGESTIONS  
- Sends intro message
- Creates and sends multiple event cards with:
  - Activity name
  - Location with address
  - Date (YYYY-MM-DD format)
  - Start and end times
  - Description
  - Generated images

### FINAL_PLAN
- Extracts event details from AI response
- Creates event card
- Creates group chat for attendees
- Sends plan to all available users

### FOLLOW_UP
Simple text message to continue conversation or clarify preferences.

## Benefits

1. **Real-time Response**: Activates when the conversation is actually happening
2. **Context-Aware**: Considers full conversation history when deciding actions
3. **Adaptive**: Can handle different conversation states and user responses
4. **Non-Intrusive**: Won't spam users (30-minute minimum interval between runs)
5. **Intelligent**: Makes decisions based on conversation flow rather than rigid timing
6. **Natural Flow**: Responds to group activity rather than arbitrary schedules

## Throttling & Controls

### Smart Anti-Double-Messaging
- **Chat-Specific Logic**: Checks if the bot was the last to send a message in the specific chat that triggered the analysis
- **30-minute window**: If the bot messaged recently in that chat, prevents analysis to avoid double-messaging
- **User-Responsive**: If a user sends a message after the bot's message, analysis can run immediately
- **Natural Conversation Flow**: Allows back-and-forth conversation without artificial delays

### Active Hours
- **8 AM to 11 PM** Pacific Time only
- Respects users' sleep schedules
- Messages outside these hours are queued for the next active period

### Trigger Conditions
- Only triggers on **user messages** (not bot messages)
- Requires valid chat and chatbot documents
- Graceful error handling for edge cases

## Testing

### Manual Testing via HTTP
```bash
# Test the new system manually via HTTP request
curl -X POST https://your-region-your-project.cloudfunctions.net/manualAnalyzeAndSendMessages
```

### Manual Testing via Function
```javascript
// Test the analysis function directly
exports.testAnalyzeAndSendMessages = analyzeChatsAndDecideMessages;
```

### Local Testing
```bash
# Test the system manually
node test-flexible.js
```

## Technical Implementation

### Firestore Trigger
```javascript
exports.onMessageSent = functions
  .firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    // Trigger logic here
  });
```

### Database Collections Used
- **`chats`**: Main chat documents and messages
- **`analysisHistory`**: Tracks last run times to prevent spam
- **`groups`**: Created when final plans are made
- **`users`**: User information and preferences

## Migration Notes

- **No more scheduled functions**: Completely event-driven now
- Old scheduled functions are commented out but preserved for reference
- New system maintains backward compatibility with existing data structures
- Manual trigger functions are available for testing

## AI Prompt Structure

The system uses a structured prompt that:
- Explains the agent's role and capabilities
- Provides current date context
- Describes available message types
- Requests JSON-formatted responses with reasoning
- Includes full chat histories for context

## Error Handling

- Graceful fallbacks for parsing errors
- Continued processing if individual user messages fail
- Comprehensive logging for debugging
- Timeout protection for long-running operations
- Safe defaults when throttling conditions can't be checked 