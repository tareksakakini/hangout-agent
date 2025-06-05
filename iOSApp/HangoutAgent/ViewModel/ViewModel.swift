//
//  ViewModel.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/22/25.
//

import Foundation
import FirebaseFirestore
import UIKit
import FirebaseStorage

@MainActor
class ViewModel: ObservableObject {
    @Published var signedInUser: User? = nil
    @Published var users: [User] = []
    @Published var chatbots: [Chatbot] = []
    @Published var chats: [Chat] = []
    @Published var groups: [HangoutGroup] = []
    @Published var groupMessages: [String: [GroupMessage]] = [:] // groupId -> messages
    
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var groupMessageListeners: [String: ListenerRegistration] = [:]
    
    init() {
        Task {
            await loadSignedInUser()
            self.users = await getAllUsers()
            self.chatbots = await getAllChatbots()
            await loadGroupsForUser()
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
    
    func signupButtonPressed(fullname: String, username: String, email: String, password: String, homeCity: String? = nil) async -> User? {
        do {
            let authUser = try await AuthManager.shared.signup(email: email, password: password)
            let firestoreService = DatabaseManager()
            try await firestoreService.addUserToFirestore(uid: authUser.uid, fullname: fullname, username: username, email: email, homeCity: homeCity)
            let user = User(id: authUser.uid, fullname: fullname, username: username, email: email, isEmailVerified: false, homeCity: homeCity)
            print("📧 Account created successfully! Please check your email to verify your account.")
            return user
        } catch {
            print(error)
            return nil
        }
    }
    
    func signinButtonPressed(email: String, password: String) async -> User? {
        do {
            let authUser = try await AuthManager.shared.signin(email: email, password: password)
            
            // Reload user to get latest verification status
            try await AuthManager.shared.reloadUser()
            
            let firestoreService = DatabaseManager()
            var user = try await firestoreService.getUserFromFirestore(uid: authUser.uid)
            
            // Check if Firebase Auth verification status differs from Firestore
            let authVerificationStatus = AuthManager.shared.isEmailVerified()
            if authVerificationStatus != user.isEmailVerified {
                // Update Firestore to match Firebase Auth
                try await firestoreService.updateEmailVerificationStatus(uid: authUser.uid, isVerified: authVerificationStatus)
                user.isEmailVerified = authVerificationStatus
                
                if authVerificationStatus {
                    print("✅ Email verification status updated - user is now verified!")
                }
            }
            
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
    
    func createChatbotButtonPressed(id: String, name: String, subscribers: [String], schedules: ChatbotSchedules, uid: String) async {
        do {
            let firestoreService = DatabaseManager()
            let creator = users.first(where: { $0.id == uid })?.username ?? "unknown"
            let createdAt = Date()
            try await firestoreService.addChatbotToFirestore(id: id, name: name, subscribers: subscribers, schedules: schedules, creator: creator, createdAt: createdAt)
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
    
    func deleteAccountButtonPressed() async -> (success: Bool, errorMessage: String?) {
        guard let user = signedInUser else { 
            return (false, "No user signed in")
        }
        
        do {
            // Step 1: Delete Firebase Auth account first (most likely to fail)
            try await AuthManager.shared.deleteUserAuth()
            
            // Step 2: Only delete user data if Auth deletion succeeded
            let firestoreService = DatabaseManager()
            try await firestoreService.deleteUserFromFirestore(uid: user.id)
            
            DispatchQueue.main.async {
                self.signedInUser = nil
            }
            
            return (true, nil)
        } catch {
            print("Error deleting account: \(error)")
            
            // Provide user-friendly error messages
            let errorMessage: String
            if error.localizedDescription.contains("requires-recent-login") {
                errorMessage = "For security reasons, please sign out and sign back in, then try deleting your account again."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("internet") {
                errorMessage = "Network error. Please check your internet connection and try again."
            } else {
                errorMessage = "Account deletion failed. Please try again or contact support if the problem persists."
            }
            
            return (false, errorMessage)
        }
    }
    
    func loadSignedInUser() async {
        do {
            if let firebaseUser = AuthManager.shared.getCurrentUser() {
                // Reload Firebase user to get latest verification status
                try await AuthManager.shared.reloadUser()
                
                let firestoreService = DatabaseManager()
                var user = try await firestoreService.getUserFromFirestore(uid: firebaseUser.uid)
                
                // Sync verification status between Firebase Auth and Firestore
                let authVerificationStatus = AuthManager.shared.isEmailVerified()
                if authVerificationStatus != user.isEmailVerified {
                    try await firestoreService.updateEmailVerificationStatus(uid: firebaseUser.uid, isVerified: authVerificationStatus)
                    user.isEmailVerified = authVerificationStatus
                    
                    if authVerificationStatus {
                        print("✅ Email verification status synced - user is verified!")
                    }
                }
                
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
    
    // MARK: - Group Chat Methods
    
    func createGroup(name: String, participants: [String] = []) async -> Bool {
        guard let user = signedInUser else { return false }
        
        do {
            let firestoreService = DatabaseManager()
            let groupId = UUID().uuidString
            
            // Include the current user in participants if not already included
            var allParticipants = participants
            if !allParticipants.contains(user.id) {
                allParticipants.append(user.id)
            }
            
            // Get participant names
            let participantNames = await getParticipantNames(for: allParticipants)
            
            let groupData: [String: Any] = [
                "id": groupId,
                "name": name,
                "participants": allParticipants,
                "participantNames": participantNames,
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date()),
                "lastMessage": nil as String?
            ]
            
            try await firestoreService.db.collection("groups")
                .document(groupId)
                .setData(groupData)
            
            // Reload groups to update the UI
            await loadGroupsForUser()
            
            print("✅ Successfully created group: \(name) with ID: \(groupId)")
            return true
            
        } catch {
            print("❌ Error creating group: \(error)")
            return false
        }
    }
    
    private func getParticipantNames(for participantIds: [String]) async -> [String] {
        var names: [String] = []
        
        for participantId in participantIds {
            if let user = users.first(where: { $0.id == participantId }) {
                names.append(user.fullname)
            } else if let user = await getUser(uid: participantId) {
                names.append(user.fullname)
            } else {
                names.append("Unknown User")
            }
        }
        
        return names
    }
    
    func loadGroupsForUser() async {
        guard let user = signedInUser else { 
            print("❌ No signed in user, cannot load groups")
            return 
        }
        
        print("📱 Loading groups for user: \(user.fullname) (ID: \(user.id))")
        
        do {
            let firestoreService = DatabaseManager()
            // Remove the .order(by:) to avoid composite index requirement
            let groupsSnapshot = try await firestoreService.db.collection("groups")
                .whereField("participants", arrayContains: user.id)
                .getDocuments()
            
            print("📱 Found \(groupsSnapshot.documents.count) groups in Firestore")
            
            var loadedGroups: [HangoutGroup] = []
            
            for groupDoc in groupsSnapshot.documents {
                let data = groupDoc.data()
                print("📱 Processing group document: \(groupDoc.documentID)")
                print("📱 Group data: \(data)")
                
                let dateFormatter = DateFormatter()
                let group = HangoutGroup(
                    id: data["id"] as? String ?? groupDoc.documentID,
                    name: data["name"] as? String ?? "Unnamed Group",
                    participants: data["participants"] as? [String] ?? [],
                    participantNames: data["participantNames"] as? [String] ?? [],
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    eventDetails: nil, // We'll decode this separately if needed
                    lastMessage: data["lastMessage"] as? String,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                
                print("📱 Created group object: \(group.name) with \(group.participants.count) participants")
                loadedGroups.append(group)
            }
            
            // Sort locally by updatedAt in descending order
            loadedGroups.sort { $0.updatedAt > $1.updatedAt }
            
            DispatchQueue.main.async {
                self.groups = loadedGroups
                print("📱 Updated UI with \(loadedGroups.count) groups")
                
                // Start listening to messages for each group
                for group in loadedGroups {
                    self.startListeningToGroupMessages(groupId: group.id)
                }
            }
            
        } catch {
            print("❌ Error loading groups: \(error)")
        }
    }
    
    func sendGroupMessage(groupId: String, text: String) async {
        guard let user = signedInUser else { return }
        
        do {
            let firestoreService = DatabaseManager()
            let message = GroupMessage(
                id: UUID().uuidString,
                text: text,
                senderId: user.id,
                senderName: user.fullname,
                timestamp: Date()
            )
            
            // Convert to dictionary for Firestore
            let messageData: [String: Any] = [
                "id": message.id,
                "text": message.text,
                "senderId": message.senderId,
                "senderName": message.senderName,
                "timestamp": Timestamp(date: message.timestamp)
            ]
            
            try await firestoreService.db.collection("groups")
                .document(groupId)
                .collection("messages")
                .addDocument(data: messageData)
            
            // Update the group's last message and timestamp
            try await firestoreService.db.collection("groups")
                .document(groupId)
                .updateData([
                    "lastMessage": text,
                    "updatedAt": Timestamp(date: Date())
                ])
            
        } catch {
            print("Error sending group message: \(error)")
        }
    }
    
    func startListeningToGroupMessages(groupId: String) {
        print("📱 Starting to listen to group messages for group: \(groupId)")
        // Remove existing listener if any
        stopListeningToGroupMessages(groupId: groupId)
        
        let firestoreService = DatabaseManager()
        let listener = firestoreService.db.collection("groups")
            .document(groupId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] querySnapshot, error in
                if let error = error {
                    print("Error listening to group messages: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("No group messages found")
                    return
                }
                
                let messages = documents.compactMap { doc -> GroupMessage? in
                    let data = doc.data()
                    return GroupMessage(
                        id: data["id"] as? String ?? doc.documentID,
                        text: data["text"] as? String ?? "",
                        senderId: data["senderId"] as? String ?? "",
                        senderName: data["senderName"] as? String ?? "Unknown",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                
                DispatchQueue.main.async {
                    self?.groupMessages[groupId] = messages
                    print("📱 Updated \(messages.count) group messages for group: \(groupId)")
                }
            }
        
        groupMessageListeners[groupId] = listener
    }
    
    func stopListeningToGroupMessages(groupId: String) {
        print("📱 Stopping group message listener for group: \(groupId)")
        groupMessageListeners[groupId]?.remove()
        groupMessageListeners.removeValue(forKey: groupId)
    }
    
    func leaveGroup(groupId: String) async {
        guard let user = signedInUser else { return }
        
        do {
            let firestoreService = DatabaseManager()
            
            // Remove user from group participants
            try await firestoreService.db.collection("groups")
                .document(groupId)
                .updateData([
                    "participants": FieldValue.arrayRemove([user.id]),
                    "participantNames": FieldValue.arrayRemove([user.fullname])
                ])
            
            // Stop listening to messages for this group
            stopListeningToGroupMessages(groupId: groupId)
            
            // Remove group from local data
            DispatchQueue.main.async {
                self.groups.removeAll { $0.id == groupId }
            }
            
        } catch {
            print("Error leaving group: \(error)")
        }
    }
    
    // Check and update email verification status
    func checkEmailVerificationStatus() async {
        guard let user = signedInUser else { return }
        
        do {
            // Reload Firebase Auth user to get latest verification status
            try await AuthManager.shared.reloadUser()
            let authVerificationStatus = AuthManager.shared.isEmailVerified()
            
            // Update if status has changed
            if authVerificationStatus != user.isEmailVerified {
                let firestoreService = DatabaseManager()
                try await firestoreService.updateEmailVerificationStatus(uid: user.id, isVerified: authVerificationStatus)
                
                DispatchQueue.main.async {
                    self.signedInUser?.isEmailVerified = authVerificationStatus
                }
                
                if authVerificationStatus {
                    print("✅ Email verification confirmed!")
                }
            }
        } catch {
            print("❌ Error checking email verification status: \(error)")
        }
    }
    
    // Resend verification email
    func resendVerificationEmail() async -> Bool {
        do {
            try await AuthManager.shared.sendEmailVerification()
            print("📧 Verification email sent successfully!")
            return true
        } catch {
            print("❌ Error sending verification email: \(error)")
            return false
        }
    }
    
    // Send password reset email
    func sendPasswordResetEmail(email: String) async -> (success: Bool, errorMessage: String?) {
        do {
            try await AuthManager.shared.sendPasswordResetEmail(email: email)
            return (true, nil)
        } catch {
            print("❌ Error sending password reset email: \(error)")
            
            // Provide user-friendly error messages
            let errorMessage: String
            if error.localizedDescription.contains("user-not-found") {
                errorMessage = "No account found with this email address."
            } else if error.localizedDescription.contains("invalid-email") {
                errorMessage = "Please enter a valid email address."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("internet") {
                errorMessage = "Network error. Please check your internet connection and try again."
            } else {
                errorMessage = "Failed to send password reset email. Please try again."
            }
            
            return (false, errorMessage)
        }
    }
    
    // Change password
    func changePassword(currentPassword: String, newPassword: String) async -> (success: Bool, errorMessage: String?) {
        do {
            try await AuthManager.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            return (true, nil)
        } catch {
            print("❌ Error changing password: \(error)")
            
            // Provide user-friendly error messages
            let errorMessage: String
            if error.localizedDescription.contains("wrong-password") || error.localizedDescription.contains("invalid-credential") {
                errorMessage = "Current password is incorrect. Please try again."
            } else if error.localizedDescription.contains("weak-password") {
                errorMessage = "New password is too weak. Please choose a stronger password."
            } else if error.localizedDescription.contains("requires-recent-login") {
                errorMessage = "For security reasons, please sign out and sign back in, then try changing your password again."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("internet") {
                errorMessage = "Network error. Please check your internet connection and try again."
            } else {
                errorMessage = "Failed to change password. Please try again."
            }
            
            return (false, errorMessage)
        }
    }
    
    // MARK: - Profile Picture Functions
    
    func uploadProfileImage(_ image: UIImage) async -> (success: Bool, errorMessage: String?) {
        guard let user = signedInUser else {
            return (false, "No user signed in")
        }
        
        // Helper function to attempt upload with retry logic
        func attemptUpload(retryCount: Int = 0) async -> (success: Bool, errorMessage: String?) {
            do {
                // Convert image to data
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    return (false, "Failed to process image")
                }
                
                // Create a unique filename
                let fileName = "profile_\(user.id)_\(UUID().uuidString).jpg"
                
                // Get Firebase Storage reference
                let storage = Storage.storage()
                let storageRef = storage.reference()
                let profileImagesRef = storageRef.child("profile_images/\(fileName)")
                
                // Upload image data to Firebase Storage
                print("📤 Uploading profile image to Firebase Storage... (attempt \(retryCount + 1))")
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                
                let uploadResult = try await profileImagesRef.putDataAsync(imageData, metadata: metadata)
                print("✅ Upload completed successfully")
                
                // Get the download URL
                let downloadURL = try await profileImagesRef.downloadURL()
                let imageUrl = downloadURL.absoluteString
                print("📥 Download URL obtained: \(imageUrl)")
                
                // Update user's profile image URL in Firestore
                let firestoreService = DatabaseManager()
                try await firestoreService.updateUserProfileImage(uid: user.id, imageUrl: imageUrl)
                
                // Update local user object
                DispatchQueue.main.async {
                    self.signedInUser?.profileImageUrl = imageUrl
                }
                
                print("✅ Profile image uploaded and updated successfully!")
                return (true, nil)
                
            } catch {
                print("❌ Error uploading profile image (attempt \(retryCount + 1)): \(error)")
                
                // Check if it's an SSL error that we can retry
                let errorString = error.localizedDescription
                let isSSLError = errorString.contains("SSL error") || 
                               errorString.contains("-1200") || 
                               errorString.contains("secure connection") ||
                               errorString.contains("NSURLErrorDomain")
                
                // Retry logic for SSL errors (max 3 attempts)
                if isSSLError && retryCount < 2 {
                    print("🔄 SSL error detected, retrying in 2 seconds... (attempt \(retryCount + 2)/3)")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    return await attemptUpload(retryCount: retryCount + 1)
                }
                
                // Provide user-friendly error messages
                let errorMessage: String
                if isSSLError {
                    errorMessage = "Connection error occurred. This often happens in the iOS Simulator. Try using a physical device or check your network connection."
                } else if errorString.contains("network") || errorString.contains("internet") {
                    errorMessage = "Network error. Please check your internet connection and try again."
                } else if errorString.contains("permission") || errorString.contains("unauthorized") {
                    errorMessage = "Permission denied. Please try signing out and back in."
                } else if errorString.contains("quota") || errorString.contains("storage") {
                    errorMessage = "Storage limit reached. Please contact support."
                } else {
                    errorMessage = "Upload failed. Please try again."
                }
                
                return (false, errorMessage)
            }
        }
        
        return await attemptUpload()
    }
    
    func removeProfileImage() async -> (success: Bool, errorMessage: String?) {
        guard let user = signedInUser else {
            return (false, "No user signed in")
        }
        
        do {
            // Update user's profile image URL to empty string in Firestore
            let firestoreService = DatabaseManager()
            try await firestoreService.updateUserProfileImage(uid: user.id, imageUrl: "")
            
            // Update local user object
            DispatchQueue.main.async {
                self.signedInUser?.profileImageUrl = ""
            }
            
            print("✅ Profile image removed successfully!")
            return (true, nil)
        } catch {
            print("❌ Error removing profile image: \(error)")
            return (false, "Failed to remove image: \(error.localizedDescription)")
        }
    }
    
    func updateHomeCity(city: String) async -> (success: Bool, errorMessage: String?) {
        guard let user = signedInUser else {
            return (false, "No user signed in")
        }
        
        do {
            let firestoreService = DatabaseManager()
            try await firestoreService.updateHomeCity(uid: user.id, homeCity: city)
            
            // Update local user object
            DispatchQueue.main.async {
                self.signedInUser?.homeCity = city
            }
            
            return (true, nil)
        } catch {
            print("Error updating home city: \(error)")
            return (false, error.localizedDescription)
        }
    }
    
    // MARK: - Group Deletion
    func deleteGroup(groupId: String) async {
        do {
            let firestoreService = DatabaseManager()
            let groupRef = firestoreService.db.collection("groups").document(groupId)

            // Delete all messages in the group
            let messagesSnapshot = try await groupRef.collection("messages").getDocuments()
            for messageDoc in messagesSnapshot.documents {
                try await messageDoc.reference.delete()
            }

            // Delete the group document
            try await groupRef.delete()

            // Remove group from local data
            DispatchQueue.main.async {
                self.groups.removeAll { $0.id == groupId }
                self.groupMessages.removeValue(forKey: groupId)
            }
        } catch {
            print("Error deleting group: \(error)")
        }
    }
    
    // Username uniqueness check
    func isUsernameTaken(_ username: String) async -> Bool {
        do {
            let firestoreService = DatabaseManager()
            return try await firestoreService.isUsernameTaken(username: username)
        } catch {
            print("Error checking username uniqueness: \(error)")
            return false // Assume not taken on error
        }
    }
}
