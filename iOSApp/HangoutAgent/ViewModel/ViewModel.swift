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
import OneSignalFramework

@MainActor
class ViewModel: ObservableObject {
    @Published var signedInUser: User? = nil
    @Published var users: [User] = []
    @Published var chatbots: [Chatbot] = []
    @Published var chats: [Chat] = []
    @Published var groups: [HangoutGroup] = []
    @Published var groupMessages: [String: [GroupMessage]] = [:] // groupId -> messages
    @Published var groupUnreadCounts: [String: Int] = [:]
    @Published var chatUnreadCounts: [String: Int] = [:]
    
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var groupMessageListeners: [String: ListenerRegistration] = [:]
    private var userChatsListener: ListenerRegistration?
    
    init() {
        Task {
            await loadSignedInUser()
            await fetchAllUsers()
            await fetchAllChatbots()
            await loadGroupsForUser()
            startListeningToUserChats()
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
    
    func signupButtonPressed(fullname: String, username: String, email: String, password: String, homeCity: String? = nil) async -> User? {
        do {
            let authUser = try await AuthManager.shared.signup(email: email, password: password)
            
            // Register this device with OneSignal using the Firebase UID as the external user id
            OneSignal.login(authUser.uid)
            
            // Automatically detect user's timezone
            let userTimezone = TimezoneHelper.getCurrentTimezone()
            print("🌍 Detected user timezone: \(userTimezone)")
            
            let firestoreService = DatabaseManager()
            try await firestoreService.addUserToFirestore(uid: authUser.uid, fullname: fullname, username: username, email: email, homeCity: homeCity, timezone: userTimezone)
            let user = User(id: authUser.uid, fullname: fullname, username: username, email: email, isEmailVerified: false, homeCity: homeCity, timezone: userTimezone)
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
            
            // Ensure the device is linked to the correct OneSignal external user id
            OneSignal.login(authUser.uid)
            
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
            let user = try await firestoreService.getUserFromFirestore(uid: uid)
            self.signedInUser = user
            return user
        } catch {
            print(error)
            return nil
        }
    }
    
    func createChatbotButtonPressed(id: String, name: String, subscribers: [String], schedules: ChatbotSchedules, uid: String, planningStartDate: Date? = nil, planningEndDate: Date? = nil) async {
        do {
            let firestoreService = DatabaseManager()
            let creator = users.first(where: { $0.id == uid })?.username ?? "unknown"
            let createdAt = Date()
            try await firestoreService.addChatbotToFirestore(id: id, name: name, subscribers: subscribers, schedules: schedules, creator: creator, createdAt: createdAt, planningStartDate: planningStartDate, planningEndDate: planningEndDate)
            
            // Create chats and send initial messages
            await withTaskGroup(of: Void.self) { group in
                for username in subscribers {
                    if let user = users.first(where: { $0.username == username }) {
                        group.addTask {
                            do {
                                // Add subscription and create chat
                                try await firestoreService.addSubscriptionToUser(uid: user.id, chatbotId: id)
                                let chatId = try await firestoreService.createChat(chatbotId: id, userId: user.id)
                                
                                // Send initial welcome message
                                let welcomeMessage = await self.generateWelcomeMessage(
                                    userName: user.fullname,
                                    chatbotName: name,
                                    planningStartDate: planningStartDate,
                                    planningEndDate: planningEndDate
                                )
                                
                                let message = Message(
                                    id: UUID().uuidString,
                                    text: welcomeMessage,
                                    senderId: "chatbot",
                                    timestamp: Date(),
                                    side: "bot"
                                )
                                
                                try await firestoreService.sendMessageToChat(chatId: chatId, message: message)
                                print("✅ Sent welcome message to \(user.fullname)")
                                
                            } catch {
                                print("❌ Error setting up chat for \(user.fullname): \(error)")
                            }
                        }
                    }
                }
            }
        } catch {
            print(error)
        }
        await fetchAllChatbots()
        await loadSignedInUser()
    }
    
    func fetchAllChatbots() async {
        do {
            let firestoreService = DatabaseManager()
            self.chatbots = try await firestoreService.getAllChatbots()
        } catch {
            print(error)
            self.chatbots = []
        }
    }
    
    func fetchAllUsers() async {
        self.users = await getAllUsers()
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
        // Check if chat already exists locally
        if let existingChat = chats.first(where: { $0.userID == userId && $0.chatbotID == chatbotId }) {
            return existingChat
        }
        
        // If not, fetch or create from Firestore
        do {
            let firestoreService = DatabaseManager()
            // This will create the chat in Firestore if it doesn't exist.
            // The userChatsListener will automatically pick it up and add it to the local array.
            return try await firestoreService.fetchOrCreateChat(userId: userId, chatbotId: chatbotId)
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
    
    func leaveAgent(chatbotId: String) async -> (success: Bool, errorMessage: String?) {
        guard let signedInUser = signedInUser else {
            return (false, "No user signed in")
        }
        
        do {
            let firestoreService = DatabaseManager()
            
            // Remove user from chatbot subscribers
            if let idx = chatbots.firstIndex(where: { $0.id == chatbotId }) {
                var updatedChatbot = chatbots[idx]
                updatedChatbot.subscribers.removeAll { $0 == signedInUser.username }
                
                // Update chatbot in database
                let chatbotRef = firestoreService.db.collection("chatbots").document(chatbotId)
                try await chatbotRef.updateData([
                    "subscribers": updatedChatbot.subscribers
                ])
                
                // Remove subscription from user in database
                try await firestoreService.removeSubscriptionFromUser(uid: signedInUser.id, chatbotId: chatbotId)
                
                // Update local data
                DispatchQueue.main.async {
                    self.chatbots[idx] = updatedChatbot
                    self.signedInUser?.subscriptions.removeAll { $0 == chatbotId }
                    self.chats.removeAll { $0.chatbotID == chatbotId }
                }
                
                return (true, nil)
            } else {
                return (false, "Agent not found")
            }
            
        } catch {
            print("Error leaving agent: \(error)")
            return (false, "Failed to leave agent. Please try again.")
        }
    }
    
    func signoutButtonPressed() async {
        do {
            try AuthManager.shared.signout()
            // Remove external user id from OneSignal so this device no longer receives user-specific pushes
            OneSignal.logout()
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
        // Remove existing listener if any
        stopListeningToMessages(chatId: chatId)
        
        let firestoreService = DatabaseManager()
        let listener = firestoreService.listenToMessages(chatId: chatId) { [weak self] messages in
            DispatchQueue.main.async {
                if let index = self?.chats.firstIndex(where: { $0.id == chatId }) {
                    self?.chats[index].messages = messages
                    self?.updateChatUnreadCount(chatId: chatId)
                }
            }
        }
        messageListeners[chatId] = listener
    }

    func stopListeningToMessages(chatId: String) {
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
            return 
        }
        
        do {
            let firestoreService = DatabaseManager()
            // Remove the .order(by:) to avoid composite index requirement
            let groupsSnapshot = try await firestoreService.db.collection("groups")
                .whereField("participants", arrayContains: user.id)
                .getDocuments()
            
            var loadedGroups: [HangoutGroup] = []
            
            for groupDoc in groupsSnapshot.documents {
                let data = groupDoc.data()
                
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
                
                loadedGroups.append(group)
            }
            
            // Sort locally by updatedAt in descending order
            loadedGroups.sort { $0.updatedAt > $1.updatedAt }
            
            DispatchQueue.main.async {
                self.groups = loadedGroups
                
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
                    self?.updateUnreadCount(groupId: groupId)
                }
            }
        
        groupMessageListeners[groupId] = listener
    }
    
    func stopListeningToGroupMessages(groupId: String) {
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
    
    func updateTimezone(timezone: String) async -> (success: Bool, errorMessage: String?) {
        guard let user = signedInUser else {
            return (false, "No user signed in")
        }
        
        // Validate timezone
        guard TimezoneHelper.isValidTimezone(timezone) else {
            return (false, "Invalid timezone identifier")
        }
        
        do {
            let firestoreService = DatabaseManager()
            try await firestoreService.updateUserTimezone(uid: user.id, timezone: timezone)
            
            // Update local user object
            DispatchQueue.main.async {
                self.signedInUser?.timezone = timezone
            }
            
            return (true, nil)
        } catch {
            print("Error updating timezone: \(error)")
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
    
    // Generate welcome message for new chatbot
    private func generateWelcomeMessage(userName: String, chatbotName: String, planningStartDate: Date?, planningEndDate: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        
        // Format the date range
        let dateRangeText: String
        if let startDate = planningStartDate, let endDate = planningEndDate {
            let calendar = Calendar.current
            if calendar.isDate(startDate, inSameDayAs: endDate) {
                // Same day
                dateRangeText = "on \(formatter.string(from: startDate))"
            } else {
                // Date range
                dateRangeText = "between \(formatter.string(from: startDate)) and \(formatter.string(from: endDate))"
            }
        } else if let startDate = planningStartDate {
            dateRangeText = "starting \(formatter.string(from: startDate))"
        } else if let endDate = planningEndDate {
            dateRangeText = "by \(formatter.string(from: endDate))"
        } else {
            dateRangeText = "soon"
        }
        
        return """
Hi \(userName)! 👋

I'm your hangout planning assistant! I'm here to help coordinate a fun get-together for your group \(dateRangeText).

I'll be gathering everyone's availability and preferences. To get started, could you let me know if and when you're available during this time period? 😊
"""
    }
    
    func startListeningToUserChats() {
        guard let user = signedInUser else { return }
        let firestoreService = DatabaseManager()

        userChatsListener?.remove()
        userChatsListener = firestoreService.listenToUserChats(userId: user.id) { [weak self] (addedChats, modifiedChats, removedChats) in
            guard let self = self else { return }
            
            // Handle added chats
            for chat in addedChats {
                if !self.chats.contains(where: { $0.id == chat.id }) {
                    self.chats.append(chat)
                    self.startListeningToMessages(chatId: chat.id)
                }
            }
            
            // Handle modified chats
            for chat in modifiedChats {
                if let index = self.chats.firstIndex(where: { $0.id == chat.id }) {
                    let existingMessages = self.chats[index].messages
                    self.chats[index] = chat
                    self.chats[index].messages = existingMessages
                }
            }

            // Handle removed chats
            for chat in removedChats {
                if let index = self.chats.firstIndex(where: { $0.id == chat.id }) {
                    self.stopListeningToMessages(chatId: chat.id)
                    self.chats.remove(at: index)
                }
            }
        }
    }
    
    // MARK: - Unread Message Helpers
    private func updateUnreadCount(groupId: String) {
        guard let messages = groupMessages[groupId], let userId = signedInUser?.id else { return }
        let lastReadKey = "groupLastRead_\(userId)_\(groupId)"
        let lastReadDate = UserDefaults.standard.object(forKey: lastReadKey) as? Date ?? .distantPast
        let unread = messages.filter { $0.timestamp > lastReadDate }.count
        groupUnreadCounts[groupId] = unread
    }

    func markGroupMessagesAsRead(groupId: String) {
        guard let messages = groupMessages[groupId], let userId = signedInUser?.id else { return }
        if let latestTimestamp = messages.last?.timestamp {
            let lastReadKey = "groupLastRead_\(userId)_\(groupId)"
            UserDefaults.standard.set(latestTimestamp, forKey: lastReadKey)
            updateUnreadCount(groupId: groupId)
        }
    }

    private func updateChatUnreadCount(chatId: String) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatId }), let userId = signedInUser?.id else { return }
        let messages = chats[chatIndex].messages
        let lastReadKey = "chatLastRead_\(userId)_\(chatId)"
        let lastReadDate = UserDefaults.standard.object(forKey: lastReadKey) as? Date ?? .distantPast
        let unread = messages.filter { $0.timestamp > lastReadDate && $0.senderId != userId && $0.eventCard == nil }.count
        chatUnreadCounts[chatId] = unread
    }

    func markChatMessagesAsRead(chatId: String) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatId }), let userId = signedInUser?.id else { return }
        let messages = chats[chatIndex].messages
        if let latestTimestamp = messages.last?.timestamp {
            let lastReadKey = "chatLastRead_\(userId)_\(chatId)"
            UserDefaults.standard.set(latestTimestamp, forKey: lastReadKey)
            updateChatUnreadCount(chatId: chatId)
        }
    }
    
    // MARK: - Presence Helpers
    func setActiveChat(_ chatId: String?) {
        guard let uid = signedInUser?.id else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        if let chatId {
            userRef.updateData(["activeChatId": chatId]) { error in
                if let error = error {
                    print("❌ Error setting activeChatId: \(error)")
                }
            }
        } else {
            userRef.updateData(["activeChatId": FieldValue.delete()]) { error in
                if let error = error {
                    print("❌ Error clearing activeChatId: \(error)")
                }
            }
        }
    }
    
    func setActiveGroup(_ groupId: String?) {
        guard let uid = signedInUser?.id else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        if let groupId {
            userRef.updateData(["activeGroupId": groupId]) { error in
                if let error = error {
                    print("❌ Error setting activeGroupId: \(error)")
                }
            }
        } else {
            userRef.updateData(["activeGroupId": FieldValue.delete()]) { error in
                if let error = error {
                    print("❌ Error clearing activeGroupId: \(error)")
                }
            }
        }
    }
}
