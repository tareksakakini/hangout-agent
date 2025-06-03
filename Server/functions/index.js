const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { OpenAI } = require('openai');

admin.initializeApp();
const db = admin.firestore();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || functions.config().openai?.key,
});

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

      // Call OpenAI
      const completion = await openai.chat.completions.create({
        model: 'gpt-3.5-turbo',
        messages: chatHistory,
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
