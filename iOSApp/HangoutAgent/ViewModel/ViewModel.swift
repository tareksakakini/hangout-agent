//
//  ViewModel.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/22/25.
//

import Foundation
import FirebaseFirestore

@MainActor
class ViewModel: ObservableObject {
    @Published var signedInUser: User? = nil
    @Published var users: [User] = []
    @Published var chatbots: [Chatbot] = []
    @Published var chats: [Chat] = []
    
    private var messageListeners: [String: ListenerRegistration] = [:]
    
    init() {
        Task {
            await loadSignedInUser()
            self.users = await getAllUsers()
            self.chatbots = await getAllChatbots()
        }
    }
    
    func retrieveChat(username: String, chatbotID: String) -> Chat? {
        for chat in self.chats {
            if chat.userID == username && chat.chatbotID == chatbotID {
                return chat
            }
        }
        return nil
    }
    
    func botReply(messageText: String) async -> String {
        do {
            return try await generateOpenAIResponse(prompt: messageText)
        } catch {
            print("Error: \(error)")
            return messageText + ", yourself."
        }
    }
    
    func signupButtonPressed(fullname: String, username: String, email: String, password: String) async -> User? {
        do {
            let authUser = try await AuthManager.shared.signup(email: email, password: password)
            let firestoreService = DatabaseManager()
            try await firestoreService.addUserToFirestore(uid: authUser.uid, fullname: fullname, username: username, email: email)
            let user = User(id: authUser.uid, fullname: fullname, username: username, email: email)
            return user
        } catch {
            print(error)
            return nil
        }
    }
    
    func signinButtonPressed(email: String, password: String) async -> User? {
        do {
            let authUser = try await AuthManager.shared.signin(email: email, password: password)
            let firestoreService = DatabaseManager()
            let user = try await firestoreService.getUserFromFirestore(uid: authUser.uid)
            return user
        } catch {
            print(error)
            return nil
        }
    }
    
    func getUser(uid: String) async -> User? {
        do {
            let firestoreService = DatabaseManager()
            return try await firestoreService.getUserFromFirestore(uid: uid)
        } catch {
            print(error)
            return nil
        }
    }
    
    func createChatbotButtonPressed(id: String, name: String, subscribers: [String], uid: String) async {
        do {
            let firestoreService = DatabaseManager()
            
            try await firestoreService.addChatbotToFirestore(id: id, name: name, subscribers: subscribers)
            
            for username in subscribers {
                if let user = users.first(where: { $0.username == username }) {
                    try await firestoreService.addSubscriptionToUser(uid: user.id, chatbotId: id)
                    _ = try await firestoreService.createChat(chatbotId: id, userId: user.id)
                }
            }
        } catch {
            print(error)
        }
    }
    
    
    func getAllChatbots() async -> [Chatbot] {
        do {
            let firestoreService = DatabaseManager()
            return try await firestoreService.getAllChatbots()
        } catch {
            print(error)
            return []
        }
    }
    
    func getAllUsers() async -> [User] {
        do {
            let firestoreService = DatabaseManager()
            return try await firestoreService.getAllUsers()
        } catch {
            print(error)
            return []
        }
    }
    
    func fetchOrCreateChat(userId: String, chatbotId: String) async -> Chat? {
        do {
            let firestoreService = DatabaseManager()
            let chat = try await firestoreService.fetchOrCreateChat(userId: userId, chatbotId: chatbotId)
            DispatchQueue.main.async {
                self.chats.append(chat)
                self.startListeningToMessages(chatId: chat.id)
            }
            return chat
        } catch {
            print("Error fetching or creating chat: \(error)")
            return nil
        }
    }
    
    func sendMessage(chat: Chat, text: String, senderId: String, side: String, eventCard: EventCard? = nil) async {
        do {
            let firestoreService = DatabaseManager()
            let message = Message(
                id: UUID().uuidString,
                text: text,
                senderId: senderId,
                timestamp: Date(),
                side: side,
                eventCard: eventCard
            )
            try await firestoreService.sendMessageToChat(chatId: chat.id, message: message)
        } catch {
            print("Error sending message: \(error)")
        }
    }
    
    func deleteChatbot(chatbotId: String) async {
        do {
            let firestoreService = DatabaseManager()
            try await firestoreService.deleteChatbot(chatbotId: chatbotId)
            
            DispatchQueue.main.async {
                // Update local data
                self.chatbots.removeAll { $0.id == chatbotId }
                
                for i in self.users.indices {
                    self.users[i].subscriptions.removeAll { $0 == chatbotId }
                }
                
                self.chats.removeAll { $0.chatbotID == chatbotId }
            }
        } catch {
            print("Error deleting chatbot: \(error)")
        }
    }
    
    func signoutButtonPressed() async {
        do {
            try AuthManager.shared.signout()
            DispatchQueue.main.async {
                self.signedInUser = nil
            }
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    func deleteAccountButtonPressed() async {
        guard let user = signedInUser else { return }
        
        do {
            let firestoreService = DatabaseManager()
            try await firestoreService.deleteUserFromFirestore(uid: user.id)
            try await AuthManager.shared.deleteUserAuth()
            
            DispatchQueue.main.async {
                self.signedInUser = nil
            }
        } catch {
            print("Error deleting account: \(error)")
        }
    }
    
    func loadSignedInUser() async {
        do {
            if let firebaseUser = AuthManager.shared.getCurrentUser() {
                let firestoreService = DatabaseManager()
                let user = try await firestoreService.getUserFromFirestore(uid: firebaseUser.uid)
                DispatchQueue.main.async {
                    self.signedInUser = user
                }
            } else {
                DispatchQueue.main.async {
                    self.signedInUser = nil
                }
            }
        } catch {
            print("Error loading signed in user: \(error)")
        }
    }
    
    func parseAgentResponse(response: String) -> ParsedAgentResponse {
        var messageToUser = ""
        var apiCalls: [ParsedToolCall] = []
        
        // Extract <response>...</response>
        if let responseStart = response.range(of: "<response>"),
           let responseEnd = response.range(of: "</response>") {
            messageToUser = String(response[responseStart.upperBound..<responseEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract all <api_call>...</api_call> blocks
        let pattern = #"<api_call>\s*(\{[\s\S]*?\})\s*</api_call>"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        let matches = regex?.matches(in: response, range: NSRange(response.startIndex..., in: response)) ?? []
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: response) {
                let jsonString = String(response[range])
                if let jsonData = jsonString.data(using: .utf8) {
                    if let call = try? JSONDecoder().decode(ParsedToolCall.self, from: jsonData) {
                        apiCalls.append(call)
                    }
                }
            }
        }
        
        return ParsedAgentResponse(messageToUser: messageToUser, apiCalls: apiCalls)
    }
    
    func performParsedAPICalls(_ apiCalls: [ParsedToolCall], chatbot: Chatbot) async {
        guard let sender = signedInUser else { return }

        for call in apiCalls {
            switch call.function {
            case "text":
                guard
                    let recipientUsername = call.arguments["username"],
                    let messageText = call.arguments["message"],
                    let recipientUser = users.first(where: { $0.username == recipientUsername })
                else {
                    print("❌ Invalid text API call or recipient not found.")
                    continue
                }

                guard let chat = await fetchOrCreateChat(userId: recipientUser.id, chatbotId: chatbot.id) else {
                    print("❌ Could not fetch/create chat for recipient.")
                    continue
                }

                // Check if this is an event card message
                if let eventCardJson = call.arguments["eventCard"],
                   let eventCardData = eventCardJson.data(using: .utf8),
                   let eventCard = try? JSONDecoder().decode(EventCard.self, from: eventCardData) {
                    print("📋 Sending message with event card: \(eventCard.activity)")
                    await sendMessage(chat: chat, text: messageText, senderId: chatbot.id, side: "bot", eventCard: eventCard)
                } else {
                    await sendMessage(chat: chat, text: messageText, senderId: chatbot.id, side: "bot")
                }

            default:
                print("⚠️ Unknown function: \(call.function)")
            }
        }
    }
    
    func getAllChatsForChatbot(chatbotId: String) async -> [Chat] {
        do {
            let firestoreService = DatabaseManager()
            let allUsers = await getAllUsers()
            var allChats: [Chat] = []
            
            // Get all chats for this chatbot
            let chatsSnapshot = try await firestoreService.db.collection("chats")
                .whereField("chatbotId", isEqualTo: chatbotId)
                .getDocuments()
            
            for chatDoc in chatsSnapshot.documents {
                let chatData = chatDoc.data()
                guard
                    let id = chatData["id"] as? String,
                    let userId = chatData["userId"] as? String,
                    let chatbotId = chatData["chatbotId"] as? String
                else { continue }
                
                let messages = try await firestoreService.fetchMessages(chatId: id)
                // Create a new chat with all messages except the most recent one
                let chat = Chat(id: id, userID: userId, chatbotID: chatbotId, messages: Array(messages.dropLast()))
                allChats.append(chat)
            }
            
            return allChats
        } catch {
            print("Error fetching all chats for chatbot: \(error)")
            return []
        }
    }

    func startListeningToMessages(chatId: String) {
        print("📱 Starting to listen to messages for chat: \(chatId)")
        // Remove existing listener if any
        stopListeningToMessages(chatId: chatId)
        
        let firestoreService = DatabaseManager()
        let listener = firestoreService.listenToMessages(chatId: chatId) { [weak self] messages in
            print("📱 Received \(messages.count) messages update for chat: \(chatId)")
            DispatchQueue.main.async {
                if let index = self?.chats.firstIndex(where: { $0.id == chatId }) {
                    print("📱 Updating messages for chat at index: \(index)")
                    self?.chats[index].messages = messages
                    print("📱 Updated messages count: \(messages.count)")
                    
                    // Log event cards if present
                    let eventCards = messages.compactMap { $0.eventCard }
                    if !eventCards.isEmpty {
                        print("📋 Found \(eventCards.count) event cards in messages")
                        for card in eventCards {
                            print("📋 Event card for activity: \(card.activity)")
                        }
                    }
                } else {
                    print("❌ Could not find chat with id: \(chatId)")
                }
            }
        }
        messageListeners[chatId] = listener
    }

    func stopListeningToMessages(chatId: String) {
        print("📱 Stopping message listener for chat: \(chatId)")
        messageListeners[chatId]?.remove()
        messageListeners.removeValue(forKey: chatId)
    }
}
