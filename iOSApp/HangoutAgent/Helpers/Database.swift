//
//  Database.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/25/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore

class DatabaseManager {
    let db = Firestore.firestore()
    
    // MARK: - Add Functions
    
    func addUserToFirestore(uid: String, fullname: String, username: String, email: String, homeCity: String? = nil) async throws {
        let userRef = db.collection("users").document(uid)
        
        var userData: [String: Any] = [
            "uid": uid,
            "fullname": fullname,
            "username": username,
            "email": email,
            "subscriptions": [],
            "isEmailVerified": false  // Initially false, will be updated when verified
        ]
        
        // Add homeCity if provided
        if let homeCity = homeCity, !homeCity.isEmpty {
            userData["homeCity"] = homeCity
        }
        
        do {
            try await userRef.setData(userData)
            print("User added successfully!")
        } catch {
            print("Error adding user: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addChatbotToFirestore(id: String, name: String, subscribers: [String], schedules: ChatbotSchedules, creator: String, createdAt: Date, planningStartDate: Date? = nil, planningEndDate: Date? = nil) async throws {
        let chatbotRef = db.collection("chatbots").document(id)
        
        let schedulesData: [String: Any] = [
            "availabilityMessageSchedule": [
                "dayOfWeek": schedules.availabilityMessageSchedule.dayOfWeek as Any,
                "specificDate": schedules.availabilityMessageSchedule.specificDate as Any,
                "hour": schedules.availabilityMessageSchedule.hour,
                "minute": schedules.availabilityMessageSchedule.minute,
                "timeZone": schedules.availabilityMessageSchedule.timeZone
            ],
            "suggestionsSchedule": [
                "dayOfWeek": schedules.suggestionsSchedule.dayOfWeek as Any,
                "specificDate": schedules.suggestionsSchedule.specificDate as Any,
                "hour": schedules.suggestionsSchedule.hour,
                "minute": schedules.suggestionsSchedule.minute,
                "timeZone": schedules.suggestionsSchedule.timeZone
            ],
            "finalPlanSchedule": [
                "dayOfWeek": schedules.finalPlanSchedule.dayOfWeek as Any,
                "specificDate": schedules.finalPlanSchedule.specificDate as Any,
                "hour": schedules.finalPlanSchedule.hour,
                "minute": schedules.finalPlanSchedule.minute,
                "timeZone": schedules.finalPlanSchedule.timeZone
            ]
        ]
        
        var chatbotData: [String: Any] = [
            "id": id,
            "name": name,
            "subscribers": subscribers,
            "schedules": schedulesData,
            "creator": creator,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        // Add planning date range if provided
        if let startDate = planningStartDate {
            chatbotData["planningStartDate"] = Timestamp(date: startDate)
        }
        if let endDate = planningEndDate {
            chatbotData["planningEndDate"] = Timestamp(date: endDate)
        }
        
        do {
            try await chatbotRef.setData(chatbotData)
            print("Chatbot added successfully!")
        } catch {
            print("Error adding chatbot: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Get Single Document
    
    func getUserFromFirestore(uid: String) async throws -> User {
        let userRef = db.collection("users").document(uid)
        
        do {
            let document = try await userRef.getDocument()
            guard let data = document.data() else {
                throw NSError(domain: "FirestoreError", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
            }
            return User().initFromFirestore(userData: data)
        } catch {
            print("Error fetching user: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Get Collections
    
    func getAllUsers() async throws -> [User] {
        do {
            let snapshot = try await db.collection("users").getDocuments()
            return snapshot.documents.compactMap { doc in
                User().initFromFirestore(userData: doc.data())
            }
        } catch {
            print("Error fetching users: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getAllChatbots() async throws -> [Chatbot] {
        do {
            let snapshot = try await db.collection("chatbots").getDocuments()
            return snapshot.documents.compactMap { doc -> Chatbot? in
                let data = doc.data()
                guard
                    let id = data["id"] as? String,
                    let name = data["name"] as? String,
                    let subscribers = data["subscribers"] as? [String],
                    let creator = data["creator"] as? String,
                    let createdAtTimestamp = data["createdAt"] as? Timestamp
                else {
                    return nil
                }
                let createdAt = createdAtTimestamp.dateValue()
                // Parse schedules if they exist
                var schedules: ChatbotSchedules? = nil
                if let schedulesData = data["schedules"] as? [String: Any] {
                    if let availabilityData = schedulesData["availabilityMessageSchedule"] as? [String: Any],
                       let suggestionsData = schedulesData["suggestionsSchedule"] as? [String: Any],
                       let finalPlanData = schedulesData["finalPlanSchedule"] as? [String: Any] {
                        
                        let availabilitySchedule = AgentSchedule(
                            dayOfWeek: availabilityData["dayOfWeek"] as? Int,
                            specificDate: availabilityData["specificDate"] as? String,
                            hour: availabilityData["hour"] as? Int ?? 10,
                            minute: availabilityData["minute"] as? Int ?? 0,
                            timeZone: availabilityData["timeZone"] as? String ?? "America/Los_Angeles"
                        )
                        
                        let suggestionsSchedule = AgentSchedule(
                            dayOfWeek: suggestionsData["dayOfWeek"] as? Int,
                            specificDate: suggestionsData["specificDate"] as? String,
                            hour: suggestionsData["hour"] as? Int ?? 14,
                            minute: suggestionsData["minute"] as? Int ?? 0,
                            timeZone: suggestionsData["timeZone"] as? String ?? "America/Los_Angeles"
                        )
                        
                        let finalPlanSchedule = AgentSchedule(
                            dayOfWeek: finalPlanData["dayOfWeek"] as? Int,
                            specificDate: finalPlanData["specificDate"] as? String,
                            hour: finalPlanData["hour"] as? Int ?? 16,
                            minute: finalPlanData["minute"] as? Int ?? 0,
                            timeZone: finalPlanData["timeZone"] as? String ?? "America/Los_Angeles"
                        )
                        
                        schedules = ChatbotSchedules(
                            availabilityMessageSchedule: availabilitySchedule,
                            suggestionsSchedule: suggestionsSchedule,
                            finalPlanSchedule: finalPlanSchedule
                        )
                    }
                }
                
                // Parse planning date range if available
                let planningStartDate = (data["planningStartDate"] as? Timestamp)?.dateValue()
                let planningEndDate = (data["planningEndDate"] as? Timestamp)?.dateValue()
                
                return Chatbot(id: id, name: name, subscribers: subscribers, schedules: schedules, creator: creator, createdAt: createdAt, planningStartDate: planningStartDate, planningEndDate: planningEndDate)
            }
        } catch {
            print("Error fetching chatbots: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Update Functions
    
    func addSubscriptionToUser(uid: String, chatbotId: String) async throws {
        let userRef = db.collection("users").document(uid)
        
        do {
            try await userRef.updateData([
                "subscriptions": FieldValue.arrayUnion([chatbotId])
            ])
            print("Subscription added successfully!")
        } catch {
            print("Error adding subscription: \(error.localizedDescription)")
            throw error
        }
    }
    
    func createChat(chatbotId: String, userId: String) async throws -> String {
        let chatRef = db.collection("chats").document()
        let chatData: [String: Any] = [
            "id": chatRef.documentID,
            "chatbotId": chatbotId,
            "userId": userId,
            "lastMessage": "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await chatRef.setData(chatData)
        return chatRef.documentID
    }
    
    func sendMessage(chatId: String, text: String, senderId: String) async throws {
        let messageRef = db.collection("chats").document(chatId).collection("messages").document()
        let messageData: [String: Any] = [
            "id": messageRef.documentID,
            "text": text,
            "senderId": senderId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        try await messageRef.setData(messageData)
        
        // Optionally update last message in chat
        let chatRef = db.collection("chats").document(chatId)
        try await chatRef.updateData([
            "lastMessage": text,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    func fetchMessages(chatId: String) async throws -> [Message] {
        let snapshot = try await db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard
                let id = data["id"] as? String,
                let text = data["text"] as? String,
                let senderId = data["senderId"] as? String,
                let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                let side = data["side"] as? String
            else {
                return nil
            }
            return Message(id: id, text: text, senderId: senderId, timestamp: timestamp, side: side)
        }
    }
    
    func fetchOrCreateChat(userId: String, chatbotId: String) async throws -> Chat {
        let chatsRef = db.collection("chats")
        let querySnapshot = try await chatsRef
            .whereField("userId", isEqualTo: userId)
            .whereField("chatbotId", isEqualTo: chatbotId)
            .getDocuments()
        
        if let doc = querySnapshot.documents.first {
            let messages = try await fetchMessages(chatId: doc.documentID)
            return Chat(
                id: doc.documentID,
                userID: userId,
                chatbotID: chatbotId,
                messages: messages
            )
        } else {
            let newChatId = try await createChat(chatbotId: chatbotId, userId: userId)
            return Chat(
                id: newChatId,
                userID: userId,
                chatbotID: chatbotId,
                messages: []
            )
        }
    }
    
    func sendMessageToChat(chatId: String, message: Message) async throws {
        let messageRef = db.collection("chats").document(chatId).collection("messages").document(message.id)
        var messageData: [String: Any] = [
            "id": message.id,
            "text": message.text,
            "senderId": message.senderId,
            "timestamp": Timestamp(date: message.timestamp),
            "side": message.side
        ]
        
        // Add eventCard if present
        if let eventCard = message.eventCard {
            print("📋 Adding event card to message: \(eventCard.activity)")
            messageData["eventCard"] = [
                "type": eventCard.type,
                "activity": eventCard.activity,
                "location": eventCard.location,
                "date": eventCard.date,
                "startTime": eventCard.startTime,
                "endTime": eventCard.endTime,
                "description": eventCard.description,
                "imageUrl": eventCard.imageUrl,
                "attendees": eventCard.attendees
            ]
        }
        
        try await messageRef.setData(messageData)
        
        // Update last message in parent chat
        let chatRef = db.collection("chats").document(chatId)
        try await chatRef.updateData([
            "lastMessage": message.text,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    func deleteChatbot(chatbotId: String) async throws {
        let batch = db.batch()
        
        // 1. Delete the chatbot document
        let chatbotRef = db.collection("chatbots").document(chatbotId)
        batch.deleteDocument(chatbotRef)
        
        // 2. Find and delete all chats associated with the chatbot
        let chatsSnapshot = try await db.collection("chats")
            .whereField("chatbotId", isEqualTo: chatbotId)
            .getDocuments()
        
        for chatDoc in chatsSnapshot.documents {
            batch.deleteDocument(chatDoc.reference)
        }
        
        // 3. Remove chatbot ID from all users' subscriptions
        let usersSnapshot = try await db.collection("users").getDocuments()
        
        for userDoc in usersSnapshot.documents {
            if var subscriptions = userDoc.data()["subscriptions"] as? [String],
               subscriptions.contains(chatbotId) {
                subscriptions.removeAll { $0 == chatbotId }
                
                batch.updateData([
                    "subscriptions": subscriptions
                ], forDocument: userDoc.reference)
            }
        }
        
        // 4. Commit the batch
        try await batch.commit()
        print("Chatbot and related data deleted successfully!")
    }
    
    func deleteUserFromFirestore(uid: String) async throws {
        let userRef = db.collection("users").document(uid)

        // 1. Remove user from chatbot subscribers (OUTSIDE batch)
        let chatbotsSnapshot = try await db.collection("chatbots").getDocuments()
        for chatbotDoc in chatbotsSnapshot.documents {
            try await chatbotDoc.reference.updateData([
                "subscribers": FieldValue.arrayRemove([uid])
            ])
        }

        // 2. Delete all chats/messages involving this user (BATCH)
        let batch = db.batch()
        batch.deleteDocument(userRef)

        let chatsSnapshot = try await db.collection("chats")
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        for chatDoc in chatsSnapshot.documents {
            let chatRef = chatDoc.reference
            let messagesSnapshot = try await chatRef.collection("messages").getDocuments()
            for messageDoc in messagesSnapshot.documents {
                batch.deleteDocument(messageDoc.reference)
            }
            batch.deleteDocument(chatRef)
        }

        try await batch.commit()
        print("User and related data deleted successfully!")
    }
    
    func listenToMessages(chatId: String, onUpdate: @escaping ([Message]) -> Void) -> ListenerRegistration {
        print("📱 Starting to listen to messages for chat: \(chatId)")
        return db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error fetching messages: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("❌ No documents in snapshot")
                    return
                }
                
                print("📥 Received \(documents.count) messages from Firestore")
                
                let messages = documents.compactMap { doc -> Message? in
                    let data = doc.data()
                    print("📄 Processing message document: \(doc.documentID)")
                    print("📄 Message data: \(data)")
                    
                    guard
                        let id = data["id"] as? String,
                        let senderId = data["senderId"] as? String,
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                        let side = data["side"] as? String
                    else {
                        print("❌ Failed to decode basic message fields")
                        return nil
                    }
                    
                    // Get text field, defaulting to empty string if not present
                    let text = data["text"] as? String ?? ""
                    
                    // Try to decode eventCard if present
                    var eventCard: EventCard? = nil
                    if let eventCardData = data["eventCard"] as? [String: Any] {
                        print("📄 Found eventCard data: \(eventCardData)")
                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: eventCardData)
                            eventCard = try JSONDecoder().decode(EventCard.self, from: jsonData)
                            print("✅ Successfully decoded eventCard")
                        } catch {
                            print("❌ Failed to decode eventCard: \(error)")
                        }
                    }
                    
                    let message = Message(
                        id: id,
                        text: text,
                        senderId: senderId,
                        timestamp: timestamp,
                        side: side,
                        eventCard: eventCard
                    )
                    
                    print("✅ Successfully created message with id: \(id)")
                    if eventCard != nil {
                        print("📋 Message contains eventCard for activity: \(eventCard?.activity ?? "unknown")")
                    }
                    
                    return message
                }
                
                print("📤 Sending \(messages.count) messages to UI")
                onUpdate(messages)
            }
    }
    
    // Update user email verification status
    func updateEmailVerificationStatus(uid: String, isVerified: Bool) async throws {
        let userRef = db.collection("users").document(uid)
        
        do {
            try await userRef.updateData([
                "isEmailVerified": isVerified
            ])
            print("✅ Email verification status updated for user: \(uid)")
        } catch {
            print("❌ Error updating email verification status: \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateUserProfileImage(uid: String, imageUrl: String) async throws {
        let userRef = db.collection("users").document(uid)
        
        do {
            try await userRef.updateData([
                "profileImageUrl": imageUrl
            ])
            print("✅ Profile image URL updated successfully!")
        } catch {
            print("❌ Error updating profile image URL: \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateHomeCity(uid: String, homeCity: String) async throws {
        let userRef = db.collection("users").document(uid)
        
        do {
            try await userRef.updateData([
                "homeCity": homeCity
            ])
            print("✅ Home city updated successfully!")
        } catch {
            print("❌ Error updating home city: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Check if username is taken
    func isUsernameTaken(username: String) async throws -> Bool {
        let usersRef = db.collection("users")
        let querySnapshot = try await usersRef.whereField("username", isEqualTo: username).getDocuments()
        return !querySnapshot.documents.isEmpty
    }
}
