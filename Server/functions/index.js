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
  const today = new Date().toISOString().split('T')[0];
  const chatDoc = await db.collection('chats').doc(chatId).get();
  const chatData = chatDoc.data();
  const chatbotId = chatData.chatbotId;
  const chatbotDoc = await db.collection('chatbots').doc(chatbotId).get();
  const chatbotData = chatbotDoc.data();
  const chatbotName = chatbotData.name;
  const subscribers = chatbotData.subscribers;
  return `You are a helpful and useful assistant. Today's date is ${today}. The user is chatting with ${chatbotName}, which has ${subscribers.length} subscribers.`;
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
