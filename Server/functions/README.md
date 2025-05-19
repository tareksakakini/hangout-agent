# Hangout Agent Cloud Functions

This directory contains the Google Cloud Functions for the Hangout Agent app. The main function sends weekly messages to all chatbot subscribers every Friday at 10 AM.

## Setup

1. Install Firebase CLI if you haven't already:
```bash
npm install -g firebase-tools
```

2. Login to Firebase:
```bash
firebase login
```

3. Install dependencies:
```bash
npm install
```

## Deployment

To deploy the functions:
```bash
npm run deploy
```

## Function Details

### sendWeeklyMessages
- Trigger: Every Friday at 10 AM (America/New_York timezone)
- Action: Sends a message to all subscribers of each chatbot asking if they're free for a hangout
- Message format: "Hey [first name], are you free this weekend for a hangout?"

## Development

To test the function locally:
1. Install the Firebase emulator:
```bash
firebase init emulators
```

2. Start the emulator:
```bash
firebase emulators:start
```

## Monitoring

You can monitor the function's execution in the Firebase Console:
1. Go to Firebase Console
2. Select your project
3. Go to Functions
4. Click on the function name to view logs and execution history 