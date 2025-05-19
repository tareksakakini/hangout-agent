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
    
    func addUserToFirestore(uid: String, fullname: String, username: String, email: String) async throws {
        let userRef = db.collection("users").document(uid)
        
        let userData: [String: Any] = [
            "uid": uid,
            "fullname": fullname,
            "username": username,
            "email": email,
            "subscriptions": []
        ]
        
        do {
            try await userRef.setData(userData)
            print("User added successfully!")
        } catch {
            print("Error adding user: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addChatbotToFirestore(id: String, name: String, subscribers: [String]) async throws {
        let chatbotRef = db.collection("chatbots").document(id)
        
        let chatbotData: [String: Any] = [
            "id": id,
            "name": name,
            "subscribers": subscribers,
        ]
        
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
                    let subscribers = data["subscribers"] as? [String]
                else {
                    return nil
                }
                return Chatbot(id: id, name: name, subscribers: subscribers)
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
        let messageData: [String: Any] = [
            "id": message.id,
            "text": message.text,
            "senderId": message.senderId,
            "timestamp": Timestamp(date: message.timestamp),
            "side": message.side
        ]
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
        return db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching messages: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                let messages = documents.compactMap { doc -> Message? in
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
                
                onUpdate(messages)
            }
    }
}
