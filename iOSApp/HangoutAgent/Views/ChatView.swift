import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var user: User
    @State var chatbot: Chatbot
    var chat: Chat? {
        vm.chats.first(where: { $0.userID == user.id && $0.chatbotID == chatbot.id })
    }
    
    @State var messageText: String = ""
    
    @State private var showAgentInfo = false
    @State private var isProcessingAgentAction = false
    @State private var agentActionError: String? = nil
    
    var body: some View {
        NavigationStack {
            Divider().padding(.top, 10)
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    if let chat {
                        VStack(spacing: 12) {
                            ForEach(0..<chat.messages.count, id: \.self) { index in
                                let message = chat.messages[index]
                                if message.eventCard != nil {
                                    // Check if this is the start of a new group of event cards
                                    let isStartOfGroup = index == 0 || chat.messages[index - 1].eventCard == nil
                                    
                                    if isStartOfGroup {
                                        // Find all consecutive event cards
                                        let eventCards = chat.messages[index...].prefix { $0.eventCard != nil }.compactMap { $0.eventCard }
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(eventCards, id: \.id) { eventCard in
                                                    EventCardView(eventCard: eventCard)
                                                        .frame(width: UIScreen.main.bounds.width * 0.8)
                                                }
                                            }
                                            .padding(.horizontal, 4)
                                        }
                                        .id("eventCards-\(index)")
                                    }
                                } else {
                                    // Display text message
                                    MessageView(
                                        text: message.text,
                                        alignment: message.side == "user" ? .trailing : .leading,
                                        timestamp: message.timestamp
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                    }
                }
                .onChange(of: chat?.messages.count) { oldValue, newValue in
                    scrollToBottom(using: scrollViewProxy)
                }
                .onAppear {
                    Task {
                        if chat == nil {
                            _ = await vm.fetchOrCreateChat(userId: user.id, chatbotId: chatbot.id)
                        }
                    }
                }
            }
            textbox
        }
        .navigationTitle(chatbot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAgentInfo = true }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showAgentInfo) {
            AgentInfoView(
                chatbot: chatbot,
                allUsers: vm.users,
                currentUsername: vm.signedInUser?.username ?? "",
                onLeave: {
                    Task {
                        isProcessingAgentAction = true
                        agentActionError = nil
                        guard let signedInUser = vm.signedInUser else { return }
                        do {
                            if let idx = vm.chatbots.firstIndex(where: { $0.id == chatbot.id }) {
                                var updatedChatbot = vm.chatbots[idx]
                                updatedChatbot.subscribers.removeAll { $0 == signedInUser.username }
                                let firestoreService = DatabaseManager()
                                let chatbotRef = firestoreService.db.collection("chatbots").document(chatbot.id)
                                try await chatbotRef.updateData([
                                    "subscribers": updatedChatbot.subscribers
                                ])
                                DispatchQueue.main.async {
                                    vm.chatbots[idx] = updatedChatbot
                                    vm.signedInUser?.subscriptions.removeAll { $0 == chatbot.id }
                                    showAgentInfo = false
                                    dismiss() // Pop back to chat list
                                }
                            }
                        } catch {
                            agentActionError = "Failed to leave agent. Please try again."
                        }
                        isProcessingAgentAction = false
                    }
                },
                onDelete: {
                    Task {
                        isProcessingAgentAction = true
                        agentActionError = nil
                        await vm.deleteChatbot(chatbotId: chatbot.id)
                        DispatchQueue.main.async {
                            showAgentInfo = false
                            dismiss() // Pop back to chat list
                        }
                        isProcessingAgentAction = false
                    }
                },
                isProcessing: isProcessingAgentAction,
                errorMessage: agentActionError
            )
        }
        .onDisappear {
            if let chat = chat {
                vm.stopListeningToMessages(chatId: chat.id)
            }
        }
        .onAppear {
            logChatState()
        }
        .onChange(of: chat?.messages) { oldValue, newValue in
            logChatState()
        }
    }
    
    private func logChatState() {
        if let chat {
            print("📱 Rendering chat with \(chat.messages.count) messages")
            for message in chat.messages {
                print("📱 Processing message: \(message.id)")
                if let eventCard = message.eventCard {
                    print("📋 Rendering event card for activity: \(eventCard.activity)")
                } else {
                    print("💬 Rendering text message: \(message.text)")
                }
            }
        } else {
            print("❌ No chat found for user: \(user.id) and chatbot: \(chatbot.id)")
        }
    }
    
    private func scrollToBottom(using proxy: ScrollViewProxy) {
        if let lastMessage = chat?.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

extension ChatView {
    private var textbox: some View {
        HStack {
            TextField("Type a message...", text: $messageText)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            Button(action: {
                // Store the message text and clear the field immediately
                let currentMessage = messageText
                messageText = ""
                
                Task {
                    guard let chat else { return }
                    
                    // Send user's message
                    await vm.sendMessage(chat: chat, text: currentMessage, senderId: user.id, side: "user")
                    
                    // Fetch all chats for this chatbot
                    let allChats = await vm.getAllChatsForChatbot(chatbotId: chatbot.id)
                    
                    // Generate bot's reply
                    let prompt = formatPrompt(
                        inputRequest: currentMessage,
                        chatbot: chatbot,
                        allUsers: vm.users,
                        currentUsername: vm.signedInUser?.username ?? "unknown",
                        chats: allChats
                    )
                    
                    //print(prompt)

                    let botReplyText = await vm.botReply(messageText: prompt)
                    //print(botReplyText)
                    let parsedAgentResponse = vm.parseAgentResponse(response: botReplyText)
                    
                    // Send bot's message.
                    await vm.sendMessage(chat: chat, text: parsedAgentResponse.messageToUser, senderId: chatbot.id, side: "bot")
                    // ⚙️ Execute API calls (e.g. text other group members)
                    await vm.performParsedAPICalls(parsedAgentResponse.apiCalls, chatbot: chatbot)
                    //print(parsedAgentResponse.apiCalls)
                }
            }) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(messageText.isEmpty ? Color.gray : Color.blue)
                    .clipShape(Circle())
            }
            .disabled(messageText.isEmpty)
            
        }
        .padding()
        .background(Color.white)
    }
}
