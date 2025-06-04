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

struct ChatListView: View {
    @EnvironmentObject private var vm: ViewModel
    @Binding var showCreateChatbot: Bool
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack {
                if let user = vm.signedInUser {
                    let userChatbots = vm.chatbots.filter { user.subscriptions.contains($0.id) }
                    if userChatbots.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "message")
                                .font(.system(size: 60))
                                .foregroundColor(.blue.opacity(0.4))
                            Text("No AI Agents Yet")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("You haven't created or joined any AI agents yet. Agents help you coordinate hangouts and automate planning with friends!")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button(action: { showCreateChatbot = true }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Create AI Agent")
                                }
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(radius: 4)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Spacer()
                    } else {
                        List {
                            ForEach(userChatbots) { chatbot in
                                ChatRowWithNavigation(chatbot: chatbot, user: user)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    Text("No user signed in.")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}


private struct ChatRow: View {
    let chatbot: Chatbot
    
    var body: some View {
        HStack(spacing: 16) {
            // Placeholder circle avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(chatbot.name.prefix(1))
                        .font(.title2.bold())
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(chatbot.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Tap to chat")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

private struct ChatRowWithNavigation: View {
    let chatbot: Chatbot
    let user: User
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        HStack {
            NavigationLink(destination: ChatView(user: user, chatbot: chatbot)) {
                ChatRow(chatbot: chatbot)
            }
            .buttonStyle(PlainButtonStyle()) // removes weird tap animation
        }
        // Removed swipeActions for delete
    }
}

struct CreateChatbotView: View {
    @EnvironmentObject var vm: ViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var name: String = ""
    @State var searchText: String = ""
    @State var selectedUsers: Set<String> = []
    @State var errorMessage: String?
    
    // Scheduling state variables
    @State var availabilityDay: Int = 2 // Default to Tuesday
    @State var availabilityHour: Int = 10 // Default to 10 AM
    @State var availabilityMinute: Int = 0
    
    @State var suggestionsDay: Int = 4 // Default to Thursday
    @State var suggestionsHour: Int = 14 // Default to 2 PM
    @State var suggestionsMinute: Int = 0
    
    @State var finalPlanDay: Int = 5 // Default to Friday
    @State var finalPlanHour: Int = 16 // Default to 4 PM
    @State var finalPlanMinute: Int = 0
    
    @State var timeZone: String = "America/Los_Angeles"
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return []
        } else {
            // Filter out the current user since they'll be added by default
            return vm.users.filter { user in
                let searchLower = searchText.lowercased()
                let matchesSearch = user.username.lowercased().contains(searchLower) || 
                                  user.fullname.lowercased().contains(searchLower)
                let isNotCurrentUser = user.id != vm.signedInUser?.id
                return matchesSearch && isNotCurrentUser
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemGray6),
                        Color(.systemGray5).opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header section
                        VStack(spacing: 16) {
                            // Icon
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 35, weight: .medium))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: Color.blue.opacity(0.3), radius: 15, x: 0, y: 8)
                            
                            VStack(spacing: 8) {
                                Text("Create AI Agent")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("Build your personalized hangout coordinator")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Main form card
                        VStack(spacing: 24) {
                            // Agent name section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "textformat")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Agent Name")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                TextField("Enter agent name...", text: $name)
                                    .font(.system(size: 16, weight: .medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(name.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // Search section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Add Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                    
                                    TextField("Search by name or username...", text: $searchText)
                                        .font(.system(size: 16, weight: .medium))
                                        .textInputAutocapitalization(.never)
                                        .disableAutocorrection(true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(searchText.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                                )
                                
                                // Search results
                                if !filteredUsers.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(filteredUsers) { user in
                                            UserSearchResultView(
                                                user: user,
                                                isSelected: selectedUsers.contains(user.username),
                                                onTap: {
                                                    if selectedUsers.contains(user.username) {
                                                        selectedUsers.remove(user.username)
                                                    } else {
                                                        selectedUsers.insert(user.username)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            
                            // Selected subscribers section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Selected Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(selectedUsers.count + 1)") // +1 for creator
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                
                                // Show creator first
                                if let currentUser = vm.signedInUser {
                                    SelectedUserRowView(
                                        user: currentUser,
                                        isCreator: true,
                                        onRemove: nil
                                    )
                                }
                                
                                // Show selected users
                                ForEach(Array(selectedUsers), id: \.self) { username in
                                    if let user = vm.users.first(where: { $0.username == username }) {
                                        SelectedUserRowView(
                                            user: user,
                                            isCreator: false,
                                            onRemove: {
                                                selectedUsers.remove(username)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(16)
                            
                            // Scheduling section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Agent Schedule")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                Text("Configure when your agent should send different types of messages")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 16) {
                                    // Availability Messages
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ask for Availability")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $availabilityDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $availabilityHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $availabilityMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Suggestions
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Send Suggestions")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $suggestionsDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $suggestionsHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $suggestionsMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Final Plan
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Send Final Plan")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $finalPlanDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $finalPlanHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $finalPlanMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(16)
                            
                            // Error message
                            if let errorMessage = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
                        .padding(.horizontal, 20)
                        
                        // Create button
                        Button(action: createChatbot) {
                            HStack(spacing: 12) {
                                if name.isEmpty {
                                    Image(systemName: "textformat")
                                        .font(.system(size: 16, weight: .medium))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                Text("Create AI Agent")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: name.isEmpty ? 
                                        [Color.gray.opacity(0.6), Color.gray.opacity(0.4)] :
                                        [Color.blue, Color.blue.opacity(0.8)]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: name.isEmpty ? Color.clear : Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                            .scaleEffect(name.isEmpty ? 1.0 : 1.02)
                            .animation(.easeInOut(duration: 0.2), value: name.isEmpty)
                        }
                        .disabled(name.isEmpty)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            Task {
                vm.users = await vm.getAllUsers()
            }
        }
    }
    
    func createChatbot() {
        Task {
            let chatbotID = UUID().uuidString
            if let user = vm.signedInUser {
                // Always include the creator and selected users
                var subscribers = Array(selectedUsers)
                subscribers.append(user.username)
                
                // Create schedules
                let schedules = ChatbotSchedules(
                    availabilityMessageSchedule: AgentSchedule(
                        dayOfWeek: availabilityDay,
                        hour: availabilityHour,
                        minute: availabilityMinute,
                        timeZone: timeZone
                    ),
                    suggestionsSchedule: AgentSchedule(
                        dayOfWeek: suggestionsDay,
                        hour: suggestionsHour,
                        minute: suggestionsMinute,
                        timeZone: timeZone
                    ),
                    finalPlanSchedule: AgentSchedule(
                        dayOfWeek: finalPlanDay,
                        hour: finalPlanHour,
                        minute: finalPlanMinute,
                        timeZone: timeZone
                    )
                )
                
                await vm.createChatbotButtonPressed(id: chatbotID, name: name, subscribers: subscribers, schedules: schedules, uid: user.id)
                vm.chatbots = await vm.getAllChatbots()
                vm.signedInUser = await vm.getUser(uid: user.id)
                dismiss()
            }
        }
    }
}

struct UserSearchResultView: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile picture
                if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.blue)
                                )
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                        case .failure(_):
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(user.fullname.prefix(1).uppercased())
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.blue)
                                )
                        @unknown default:
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(user.fullname.prefix(1).uppercased())
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.blue)
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(user.fullname.prefix(1).uppercased())
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.blue)
                        )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullname)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("@\(user.username)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SelectedUserRowView: View {
    let user: User
    let isCreator: Bool
    let onRemove: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.blue)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    case .failure(_):
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(user.fullname.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)
                            )
                    @unknown default:
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(user.fullname.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)
                            )
                    }
                }
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(user.fullname.prefix(1).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                    )
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.fullname)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if isCreator {
                        Text("Creator")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Text("@\(user.username)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Remove button (only for non-creators)
            if !isCreator, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(10)
    }
}

struct HomeView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedTab = 0
    @State private var showCreateChatbot = false
    
    var body: some View {
        if vm.signedInUser != nil {
            NavigationStack {
                TabView(selection: $selectedTab) {
                    ChatListView(showCreateChatbot: $showCreateChatbot)
                        .tabItem {
                            Image(systemName: "message")
                            Text("Chats")
                        }
                        .tag(0)
                    
                    GroupListView()
                        .tabItem {
                            Image(systemName: "person.3")
                            Text("Groups")
                        }
                        .tag(1)
                    
                    ProfileView()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                        .tag(2)
                }
                .navigationTitle(selectedTab == 0 ? "Chats" : selectedTab == 1 ? "Groups" : "Profile")
                .toolbar {
                    if selectedTab == 0 {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showCreateChatbot = true
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showCreateChatbot) {
                    CreateChatbotView()
                        .environmentObject(vm)
                }
            }
        } else {
            ProgressView()
        }
    }
}

struct EmailVerificationView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var isCheckingVerification = false
    @State private var isResendingEmail = false
    @State private var showSuccessMessage = false
    @State private var showNotVerifiedMessage = false
    @State private var emailResent = false
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Email icon
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.bottom, 10)
                
                // Title
                Text("Verify Your Email")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                
                // Subtitle
                VStack(spacing: 8) {
                    Text("We sent a verification link to:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(vm.signedInUser?.email ?? "your email")
                        .font(.title3.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Instructions
                Text("Please check your inbox and click the verification link to continue using the app.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Success message when verification is found
                if showSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Email verified successfully!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Not verified message
                if showNotVerifiedMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Email not verified yet")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        VStack(spacing: 4) {
                            Text("Please check your inbox (including spam/junk folder)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("and click the verification link, then try again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Email resent confirmation
                if emailResent {
                    HStack {
                        Image(systemName: "paperplane.circle.fill")
                            .foregroundColor(.blue)
                        Text("Verification email sent!")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            isCheckingVerification = true
                            // Hide any previous messages
                            showNotVerifiedMessage = false
                            showSuccessMessage = false
                            
                            await vm.checkEmailVerificationStatus()
                            
                            if vm.signedInUser?.isEmailVerified == true {
                                showSuccessMessage = true
                                // Brief delay to show success message before proceeding
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    // The UI will automatically update due to the state change
                                }
                            } else {
                                // Show not verified message
                                showNotVerifiedMessage = true
                                
                                // Auto-hide the message after a few seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                    showNotVerifiedMessage = false
                                }
                            }
                            
                            isCheckingVerification = false
                        }
                    }) {
                        HStack {
                            if isCheckingVerification {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text(isCheckingVerification ? "Checking..." : "I've Verified My Email")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                    .disabled(isCheckingVerification)
                    
                    Button(action: {
                        Task {
                            isResendingEmail = true
                            // Hide previous messages
                            emailResent = false
                            showNotVerifiedMessage = false
                            
                            let success = await vm.resendVerificationEmail()
                            isResendingEmail = false
                            
                            if success {
                                emailResent = true
                                // Auto-hide the confirmation after a few seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    emailResent = false
                                }
                            }
                        }
                    }) {
                        HStack {
                            if isResendingEmail {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.orange)
                            } else {
                                Image(systemName: "envelope.arrow.triangle.branch")
                            }
                            Text(isResendingEmail ? "Sending..." : "Resend Verification Email")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                        .shadow(radius: 5)
                    }
                    .disabled(isResendingEmail)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Sign out option
                Button("Sign Out") {
                    Task {
                        await vm.signoutButtonPressed()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            // Check verification status when the view appears
            Task {
                await vm.checkEmailVerificationStatus()
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var email: String = ""
    @State var password: String = ""
    @State var showWrongMessage: Bool = false
    @State var isPasswordVisible = false
    @State var isVerified = false
    @State var wrongMessage: String = " "
    @State var showForgotPassword = false
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Logo
                Image("yalla_agent_transparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding(.top, 40)
                
                // Title
                Text("Welcome Back")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                    .padding(.bottom, 20)
                
                LoginSheet
                
                // Forgot Password Button
                Button("Forgot Password?") {
                    showForgotPassword = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.top, 10)
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(vm)
        }
    }
}


extension LoginView {
    private var LoginSheet: some View {
        VStack(spacing: 16) {
            UserFields
            WrongMessage
            SignInButton
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }
    
    private var UserFields: some View {
        VStack(spacing: 16) {
            EmailField
            PasswordField
        }
    }
    
    private var EmailField: some View {
        TextField("Email", text: $email)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
    }
    
    private var PasswordField: some View {
        HStack {
            SwiftUI.Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            
            Button(action: {
                isPasswordVisible.toggle()
            }) {
                Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(.gray)
            }
            .padding(.leading, 8)
        }
    }
    
    private var WrongMessage: some View {
        Text(wrongMessage)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.top, 4)
    }
    
    private var SignInButton: some View {
        Button {
            Task {
                vm.signedInUser = await vm.signinButtonPressed(email: email, password: password)
                if vm.signedInUser != nil {
                    // Successfully signed in - dismiss back to StartingView
                    // which will handle routing to EmailVerificationView or HomeView
                    dismiss()
                }
            }
        } label: {
            Text("Sign In")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 5)
        }
        .padding(.top, 8)
    }
}

struct MessageView: View {
    @State var text: String
    @State var alignment: Alignment
    @State var timestamp: Date
    
    var body: some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 4) {
            Text(text)
                .padding()
                .background(alignment == .leading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            
            Text(formatTimestamp(timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: UIScreen.main.bounds.width / 2, alignment: alignment)
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteResult: (success: Bool, message: String)? = nil
    @State private var showDeleteResult = false
    @State private var showChangePassword = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var isUploadingImage = false
    @State private var uploadResult: (success: Bool, message: String)? = nil
    @State private var showUploadResult = false
    @State private var imageRefreshId = UUID()
    @State private var isRemovingImage = false
    @State private var showPhotoActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var showImageCrop = false
    @State private var isEditingHomeCity = false
    @State private var editedHomeCity = ""
    @State private var isUpdatingHomeCity = false
    @State private var homeCityUpdateResult: (success: Bool, message: String)? = nil
    @State private var showHomeCityUpdateResult = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // User Info Section
                if let user = vm.signedInUser {
        VStack(spacing: 20) {
                        // Profile Avatar with Edit Functionality
                        VStack(spacing: 12) {
                            ZStack {
                                if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                    // Show actual profile image
                                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                        switch phase {
                                        case .empty:
                                            // Loading state
                                            Circle()
                                                .fill(Color.black.opacity(0.1))
                                                .frame(width: 90, height: 90)
                                                .overlay(
                                                    ProgressView()
                                                        .tint(.black.opacity(0.6))
                                                )
                                        case .success(let image):
                                            // Successfully loaded image
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 90, height: 90)
                                                .clipShape(Circle())
                                        case .failure(_):
                                            // Failed to load - show fallback
                                            Circle()
                                                .fill(Color.black)
                                                .frame(width: 90, height: 90)
                                                .overlay(
                                                    Text(user.fullname.prefix(1))
                                                        .font(.system(size: 32, weight: .medium, design: .rounded))
                                                        .foregroundColor(.white)
                                                )
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                    .id(imageRefreshId)
                                } else {
                                    // Default avatar with initials
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 90, height: 90)
                                        .overlay(
                                            Text(user.fullname.prefix(1))
                                                .font(.system(size: 32, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)
                                        )
                                }
                                
                                // Edit button overlay
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Button(action: {
                                            showPhotoActionSheet = true
                                        }) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        }
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                    .offset(x: 30, y: 30)
                            }
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                            
                            // Upload/Remove status
                            if isUploadingImage {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.black.opacity(0.6))
                                    Text("Uploading...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(16)
                            } else if isRemovingImage {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.black.opacity(0.6))
                                    Text("Removing...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(16)
                            }
                            
                            // Upload/Remove result message
                            if showUploadResult, let result = uploadResult {
                                HStack(spacing: 6) {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(result.success ? .black.opacity(0.6) : .black.opacity(0.7))
                                    Text(result.message)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(16)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        
                        // User Info Card - Clean minimal design
                        VStack(spacing: 24) {
                            Text(user.fullname)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 20) {
                                // Username row
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Username")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        Text(user.username)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    
            Spacer()
                                }
                                
                                // Subtle divider
                                Rectangle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(height: 1)
                                
                                // Email row
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "envelope")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Email")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        Text(user.email)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Verification status - subtle design
                                    if user.isEmailVerified {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.black.opacity(0.6))
                                            Text("Verified")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.black.opacity(0.6))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)
                                    } else {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.circle")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.black.opacity(0.6))
                                            Text("Unverified")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.black.opacity(0.6))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                }
                                
                                // Subtle divider
                                Rectangle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(height: 1)
                                
                                // Home City row
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "location.circle")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Home City")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        
                                        if isEditingHomeCity {
                                            HStack(spacing: 8) {
                                                TextField("Enter your city", text: $editedHomeCity)
                                                    .font(.system(size: 16, weight: .medium))
                                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                                    .textInputAutocapitalization(.words)
                                                    .disableAutocorrection(true)
                                                
                                                if isUpdatingHomeCity {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                        .tint(.black.opacity(0.6))
                                                } else {
                                                    HStack(spacing: 4) {
                                                        Button("Save") {
                                                            Task {
                                                                await updateHomeCity()
                                                            }
                                                        }
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.blue)
                                                        .disabled(editedHomeCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                                        
                                                        Button("Cancel") {
                                                            isEditingHomeCity = false
                                                            editedHomeCity = user.homeCity ?? ""
                                                        }
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.gray)
                                                    }
                                                }
                                            }
                                        } else {
                                            Text(user.homeCity?.isEmpty == false ? user.homeCity! : "Not set")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(user.homeCity?.isEmpty == false ? .primary : .black.opacity(0.4))
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if !isEditingHomeCity {
                                        Button("Edit") {
                                            editedHomeCity = user.homeCity ?? ""
                                            isEditingHomeCity = true
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(28)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                
                // Home city update result message
                if showHomeCityUpdateResult, let result = homeCityUpdateResult {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.success ? .black.opacity(0.7) : .black.opacity(0.7))
                        Text(result.message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Account deletion result message
                if showDeleteResult, let result = deleteResult {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.success ? .black.opacity(0.7) : .black.opacity(0.7))
                        Text(result.message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Action Buttons Section - Clean design
                VStack(spacing: 16) {
                    // Change Password Button
                    Button(action: {
                        showChangePassword = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "key")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black.opacity(0.7))
                            Text("Change Password")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black.opacity(0.3))
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    }
                    
                    // Sign Out Button
            Button(action: {
                Task {
                    await vm.signoutButtonPressed()
                }
            }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.square")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black.opacity(0.7))
                Text("Sign Out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black.opacity(0.3))
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    }
                    
                    // Delete Account Button - Subtle design
            Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 12) {
                            if isDeletingAccount {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black.opacity(0.7))
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.black.opacity(0.7))
                            }
                            Text(isDeletingAccount ? "Deleting Account..." : "Delete Account")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            if !isDeletingAccount {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.black.opacity(0.3))
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isDeletingAccount)
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGray6))
        .navigationTitle("Profile")
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordView()
                .environmentObject(vm)
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                isDeletingAccount = true
                Task {
                    let result = await vm.deleteAccountButtonPressed()
                    
                    DispatchQueue.main.async {
                        isDeletingAccount = false
                        deleteResult = (success: result.success, message: result.errorMessage ?? "Account deleted successfully")
                        showDeleteResult = true
                        
                        // Auto-hide the message after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            showDeleteResult = false
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone. Your account and all associated data will be permanently deleted.")
        }
        .confirmationDialog(
            "Profile Picture",
            isPresented: $showPhotoActionSheet,
            titleVisibility: .visible
        ) {
            if let user = vm.signedInUser, let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                // User has a profile picture - show change and remove options
                Button("Change Photo") {
                    showPhotoPicker = true
                }
                
                Button("Remove Photo", role: .destructive) {
                    Task {
                        await removeProfileImage()
                    }
                }
                
                Button("Cancel", role: .cancel) { }
            } else {
                // User has no profile picture - show add option
                Button("Add Photo") {
                    showPhotoPicker = true
                }
                
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            if let user = vm.signedInUser, let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                Text("Choose an option for your profile picture")
            } else {
                Text("Add a profile picture to personalize your account")
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: $showImageCrop) {
            if let image = selectedImage {
                ImageCropView(
                    image: image,
                    onCrop: { croppedImage in
                        Task {
                            await uploadProfileImage(croppedImage)
                        }
                        showImageCrop = false
                        selectedImage = nil
                    },
                    onCancel: {
                        showImageCrop = false
                        selectedImage = nil
                    }
                )
            }
        }
        .onChange(of: vm.signedInUser?.profileImageUrl) { oldValue, newValue in
            // Force image refresh when profile URL changes
            if oldValue != newValue && newValue != nil {
                imageRefreshId = UUID()
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue {
                    // Convert PhotosPickerItem to UIImage for cropping
                    do {
                        guard let imageData = try await photoItem.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: imageData) else {
                            uploadResult = (false, "Failed to process image")
                            showUploadResult = true
                            selectedPhotoItem = nil
                            return
                        }
                        
                        DispatchQueue.main.async {
                            self.selectedImage = uiImage
                            self.showImageCrop = true
                            self.selectedPhotoItem = nil // Clear the picker selection
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.uploadResult = (false, "Failed to load image")
                            self.showUploadResult = true
                            self.selectedPhotoItem = nil
                        }
                    }
                }
            }
        }
    }
    
    private func uploadProfileImage(_ uiImage: UIImage) async {
        isUploadingImage = true
        showUploadResult = false
        
        // Upload the image
        let result = await vm.uploadProfileImage(uiImage)
        
        DispatchQueue.main.async {
            self.isUploadingImage = false
            self.uploadResult = (result.success, result.success ? "Profile picture updated!" : result.errorMessage ?? "Upload failed")
            self.showUploadResult = true
            
            // Force image refresh on successful upload
            if result.success {
                self.imageRefreshId = UUID()
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showUploadResult = false
            }
        }
    }
    
    private func removeProfileImage() async {
        isRemovingImage = true
        showUploadResult = false
        
        let result = await vm.removeProfileImage()
        
        DispatchQueue.main.async {
            self.isRemovingImage = false
            self.uploadResult = (result.success, result.success ? "Profile picture removed!" : result.errorMessage ?? "Failed to remove profile picture")
            self.showUploadResult = true
            
            // Force image refresh on successful removal
            if result.success {
                self.imageRefreshId = UUID()
                // Clear the selected photo item to ensure PhotosPicker works for next selection
                self.selectedPhotoItem = nil
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showUploadResult = false
            }
        }
    }
    
    private func updateHomeCity() async {
        isUpdatingHomeCity = true
        showHomeCityUpdateResult = false
        
        let result = await vm.updateHomeCity(city: editedHomeCity.trimmingCharacters(in: .whitespacesAndNewlines))
        
        DispatchQueue.main.async {
            self.isUpdatingHomeCity = false
            self.homeCityUpdateResult = (result.success, result.success ? "Home city updated successfully!" : result.errorMessage ?? "Failed to update home city")
            self.showHomeCityUpdateResult = true
            
            if result.success {
                self.isEditingHomeCity = false
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showHomeCityUpdateResult = false
            }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    @State private var isCurrentPasswordVisible = false
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    private var canChangePassword: Bool {
        !currentPassword.isEmpty && 
        !newPassword.isEmpty && 
        !confirmPassword.isEmpty && 
        newPassword == confirmPassword && 
        newPassword.count >= 6
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Compact header (removed duplicate title)
                VStack(spacing: 8) {
                    Image(systemName: "key.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)
                
                // Result message (compact)
                if showResult {
                    HStack(spacing: 8) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isSuccess ? .green : .red)
                        Text(resultMessage)
                            .font(.subheadline)
                            .foregroundColor(isSuccess ? .green : .red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background((isSuccess ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Form fields (with distinct white backgrounds)
                VStack(spacing: 16) {
                    // Current password
                    HStack {
                        SwiftUI.Group {
                            if isCurrentPasswordVisible {
                                TextField("Current password", text: $currentPassword)
                            } else {
                                SecureField("Current password", text: $currentPassword)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        
                        Button(action: { isCurrentPasswordVisible.toggle() }) {
                            Image(systemName: isCurrentPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    // New password
                    VStack(spacing: 4) {
                        HStack {
                            SwiftUI.Group {
                                if isNewPasswordVisible {
                                    TextField("New password", text: $newPassword)
                                } else {
                                    SecureField("New password", text: $newPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            
                            Button(action: { isNewPasswordVisible.toggle() }) {
                                Image(systemName: isNewPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        if !newPassword.isEmpty && newPassword.count < 6 {
                            HStack {
                                Text("At least 6 characters required")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                    
                    // Confirm password
                    VStack(spacing: 4) {
                        HStack {
                            SwiftUI.Group {
                                if isConfirmPasswordVisible {
                                    TextField("Confirm new password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm new password", text: $confirmPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            
                            Button(action: { isConfirmPasswordVisible.toggle() }) {
                                Image(systemName: isConfirmPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            HStack {
                                Text("Passwords don't match")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Action button
                Button(action: {
                    Task { await changePassword() }
                }) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14))
                        }
                        Text(isLoading ? "Updating..." : "Update Password")
                    .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canChangePassword && !isLoading ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                }
                .disabled(!canChangePassword || isLoading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Spacer()
        }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func changePassword() async {
        isLoading = true
        showResult = false
        
        let result = await vm.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        
        isLoading = false
        isSuccess = result.success
        
        if result.success {
            resultMessage = "Password updated successfully!"
            
            // Clear the form
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            
            // Auto-dismiss after success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } else {
            resultMessage = result.errorMessage ?? "Update failed"
        }
        
        showResult = true
        
        // Auto-hide error message
        if !result.success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                showResult = false
            }
        }
    }
}

struct SignupView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var fullname: String = ""
    @State var username: String = ""
    @State var email: String = ""
    @State var password: String = ""
    @State var homeCity: String = ""
    @State var goToNextScreen: Bool = false
    @State var isPasswordVisible = false
    @State var user: User? = nil
    @State var showSuccessMessage = false
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Logo
                Image("yalla_agent_transparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding(.top, 40)
                
                // Title
                Text("Create Account")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                    .padding(.bottom, 20)
                
                SignupSheet
                
                // Success message
                if showSuccessMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Account created successfully!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        Text("Please check your email to verify your account")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

extension SignupView {
    private var SignupSheet: some View {
        VStack(spacing: 16) {
            UserFields
            SignUpButton
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }
    
    private var UserFields: some View {
        VStack(spacing: 16) {
            FullnameField
            UsernameField
            EmailField
            HomeCityField
            PasswordField
        }
    }
    
    private var FullnameField: some View {
        TextField("Full Name", text: $fullname)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
    }
    
    private var UsernameField: some View {
        TextField("Username", text: $username)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
    }
    
    private var EmailField: some View {
        TextField("Email", text: $email)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
    }
    
    private var HomeCityField: some View {
        TextField("Home City", text: $homeCity)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
    }
    
    private var PasswordField: some View {
        HStack {
            SwiftUI.Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            
            Button(action: {
                isPasswordVisible.toggle()
            }) {
                Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(.gray)
            }
            .padding(.leading, 8)
        }
    }
    
    private var SignUpButton: some View {
        Button {
            Task {
                if let signedUpUser = await vm.signupButtonPressed(fullname: fullname, username: username, email: email, password: password, homeCity: homeCity) {
                    DispatchQueue.main.async {
                        vm.signedInUser = signedUpUser
                        showSuccessMessage = true
                        
                        // Auto-dismiss after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                        }
                    }
                }
            }
        } label: {
            Text("Sign Up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 5)
        }
        .padding(.top, 8)
    }
}

struct StartingView: View {
    @EnvironmentObject private var vm: ViewModel
    @State var loginPressed: Bool = false
    @State var signupPressed: Bool = false
    
    var body: some View {
        NavigationStack {
            if let user = vm.signedInUser {
                // User is signed in -> check verification status
                if user.isEmailVerified {
                    // Verified user -> go to HomeView
                HomeView()
                } else {
                    // Unverified user -> go to EmailVerificationView
                    EmailVerificationView()
                }
            } else {
                // Not signed in -> show login/signup options
                ZStack {
                    Color(.systemGray6)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 40) {
                        Image("yalla_agent_transparent")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(.top, 60)
                        
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Button(action: {
                                loginPressed = true
                            }) {
                                Text("Log In")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            }
                            .padding(.horizontal, 40)
                            .navigationDestination(isPresented: $loginPressed) {
                                LoginView()
                            }
                            
                            Button(action: {
                                signupPressed = true
                            }) {
                                Text("Sign Up")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.blue)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                                    .shadow(radius: 4)
                            }
                            .padding(.horizontal, 40)
                            .navigationDestination(isPresented: $signupPressed) {
                                SignupView()
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

struct EventCardView: View {
    let eventCard: EventCard
    @State private var showEventDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Image section
            AsyncImage(url: URL(string: eventCard.imageUrl)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(height: 120)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            
            // Content section
            VStack(alignment: .leading, spacing: 8) {
                // Activity title
                Text(eventCard.activity)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Location
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text(eventCard.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Date and time
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("\(formatDate(eventCard.date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.green)
                    Text("\(eventCard.startTime) - \(eventCard.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Description
                Text(eventCard.description)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.top, 4)
                
                // Attendees if available
                if let attendees = eventCard.attendees, !attendees.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text("Attendees:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // See Details button
                Button(action: {
                    showEventDetail = true
                }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("See Details")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
        .sheet(isPresented: $showEventDetail) {
            EventDetailView(eventCard: eventCard)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEEE, MMM d, yyyy"
        return displayFormatter.string(from: date)
    }
}

struct EventDetailView: View {
    let eventCard: EventCard
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Image Section
                    AsyncImage(url: URL(string: eventCard.imageUrl)) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 250)
                                .overlay(
                                    ProgressView()
                                        .tint(.gray)
                                )
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 250)
                                .clipped()
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 250)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        Text("Image not available")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    // Event Information
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        Text(eventCard.activity)
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // Date & Time Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "calendar")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text(formatDate(eventCard.date))
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "clock")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.green)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Time")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text("\(eventCard.startTime) - \(eventCard.endTime)")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Location Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.red)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text(eventCard.location)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Description Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About this event")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text(eventCard.description)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Attendees Section (if available)
                        if let attendees = eventCard.attendees, !attendees.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Who's coming")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(attendees, id: \.self) { attendee in
                                        AttendeeRowView(attendeeName: attendee)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.5))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGray6))
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        return displayFormatter.string(from: date)
    }
}

struct AttendeeRowView: View {
    let attendeeName: String
    @EnvironmentObject private var vm: ViewModel
    
    private var matchedUser: User? {
        // Try to find user by full name first, then by username
        return vm.users.first { user in
            user.fullname.lowercased() == attendeeName.lowercased() ||
            user.username.lowercased() == attendeeName.lowercased()
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture or initials
            if let user = matchedUser,
               let profileImageUrl = user.profileImageUrl,
               !profileImageUrl.isEmpty {
                // Show actual profile picture
                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                    switch phase {
                    case .empty:
                        // Loading state
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.blue)
                            )
                    case .success(let image):
                        // Successfully loaded profile image
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    case .failure(_):
                        // Failed to load - show initials fallback
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(attendeeName.prefix(1).uppercased())
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            )
                    @unknown default:
                        // Default fallback
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(attendeeName.prefix(1).uppercased())
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            )
                    }
                }
            } else {
                // No profile picture available - show initials
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(attendeeName.prefix(1).uppercased())
                            .font(.caption.weight(.medium))
                            .foregroundColor(.blue)
                    )
            }
            
            // Attendee name
            Text(attendeeName)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Online indicator (if user is found in the system)
            if matchedUser != nil {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct ForgotPasswordView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Icon
                    Image(systemName: "key.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.bottom, 10)
                    
                    // Title
                    Text("Reset Password")
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                    
                    // Instructions
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    // Result message
                    if showResult {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isSuccess ? .green : .red)
                                Text(isSuccess ? "Reset Email Sent!" : "Reset Failed")
                                    .font(.headline)
                                    .foregroundColor(isSuccess ? .green : .red)
                            }
                            
                            Text(resultMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .background((isSuccess ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Email input and button
                    VStack(spacing: 16) {
                        TextField("Email Address", text: $email)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        Button(action: {
                            Task {
                                await sendPasswordReset()
                            }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isLoading ? "Sending..." : "Send Reset Email")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(email.isEmpty || isLoading ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                        }
                        .disabled(email.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sendPasswordReset() async {
        isLoading = true
        showResult = false
        
        let result = await vm.sendPasswordResetEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        
        isLoading = false
        isSuccess = result.success
        
        if result.success {
            resultMessage = "Check your inbox for password reset instructions. Don't forget to check your spam folder!"
        } else {
            resultMessage = result.errorMessage ?? "Failed to send reset email"
        }
        
        showResult = true
        
        // Auto-hide result message after some time
        DispatchQueue.main.asyncAfter(deadline: .now() + (result.success ? 5.0 : 8.0)) {
            showResult = false
            
            // If successful, auto-dismiss the sheet after showing success message
            if result.success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        }
    }
}

struct ImageCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    // Constants for better UX
    private let cropCircleSize: CGFloat = 280
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 4.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black.ignoresSafeArea()
                    
                    // Main image container
                    ZStack {
                        // The actual image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    // Pan gesture
                                    DragGesture()
                                        .onChanged { value in
                                            let newOffset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            offset = constrainOffset(newOffset, in: geometry.size)
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        },
                                    
                                    // Zoom gesture
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastScale * value
                                            scale = min(max(newScale, minScale), maxScale)
                                            
                                            // Constrain offset when scaling
                                            offset = constrainOffset(offset, in: geometry.size)
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onAppear {
                                setupInitialScale(in: geometry.size)
                            }
                        
                        // Crop overlay with circular preview
                        CircularCropOverlay(
                            cropSize: cropCircleSize,
                            screenSize: geometry.size
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("Crop Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropImage()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupInitialScale(in screenSize: CGSize) {
        // Calculate the optimal initial scale to fit the image nicely in the crop circle
        let imageSize = image.size
        _ = imageSize.width / imageSize.height // Remove unused variable warning
        
        let fitWidth = cropCircleSize
        let fitHeight = cropCircleSize
        
        let scaleToFitWidth = fitWidth / imageSize.width
        let scaleToFitHeight = fitHeight / imageSize.height
        
        // Use the larger scale factor to ensure the image covers the crop area
        let initialScale = max(scaleToFitWidth, scaleToFitHeight) * 1.1 // 10% larger for better coverage
        
        scale = min(max(initialScale, minScale), maxScale)
        lastScale = scale
    }
    
    private func constrainOffset(_ proposedOffset: CGSize, in screenSize: CGSize) -> CGSize {
        // Calculate the actual displayed image size
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Determine how the image is displayed (aspect fit)
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        
        if imageAspectRatio > screenSize.width / screenSize.height {
            // Image is wider relative to screen
            displayWidth = screenSize.width
            displayHeight = screenSize.width / imageAspectRatio
        } else {
            // Image is taller relative to screen
            displayHeight = screenSize.height
            displayWidth = screenSize.height * imageAspectRatio
        }
        
        // Apply current scale
        let scaledWidth = displayWidth * scale
        let scaledHeight = displayHeight * scale
        
        // Calculate maximum allowed offset to keep crop area filled
        let maxOffsetX = max(0, (scaledWidth - cropCircleSize) / 2)
        let maxOffsetY = max(0, (scaledHeight - cropCircleSize) / 2)
        
        // Break down the complex calculation
        let constrainedWidth = max(proposedOffset.width, -maxOffsetX)
        let finalWidth = min(constrainedWidth, maxOffsetX)
        
        let constrainedHeight = max(proposedOffset.height, -maxOffsetY)
        let finalHeight = min(constrainedHeight, maxOffsetY)
        
        return CGSize(width: finalWidth, height: finalHeight)
    }
    
    private func cropImage() {
        let imageSize = image.size
        let outputSize = CGSize(width: 400, height: 400) // Final circular image size
        
        // Calculate the crop rectangle in image coordinates
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Determine the displayed image size (how it appears on screen)
        let screenBounds = UIScreen.main.bounds
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        
        if imageAspectRatio > 1 {
            displayWidth = screenBounds.width
            displayHeight = screenBounds.width / imageAspectRatio
        } else {
            displayHeight = screenBounds.height
            displayWidth = screenBounds.height * imageAspectRatio
        }
        
        // Scale factor from display coordinates to image coordinates
        let scaleToImage = max(imageSize.width / displayWidth, imageSize.height / displayHeight)
        
        // Calculate the crop area in image coordinates
        let cropSizeInImage = cropCircleSize * scaleToImage / scale
        
        // Center of the crop area, accounting for user's pan
        let cropCenterX = (imageSize.width / 2) - (offset.width * scaleToImage / scale)
        let cropCenterY = (imageSize.height / 2) - (offset.height * scaleToImage / scale)
        
        // Define the crop rectangle
        let cropRect = CGRect(
            x: cropCenterX - cropSizeInImage / 2,
            y: cropCenterY - cropSizeInImage / 2,
            width: cropSizeInImage,
            height: cropSizeInImage
        )
        
        // Ensure crop rect is within image bounds
        let clampedCropRect = CGRect(
            x: max(0, min(cropRect.origin.x, imageSize.width - cropRect.width)),
            y: max(0, min(cropRect.origin.y, imageSize.height - cropRect.height)),
            width: min(cropRect.width, imageSize.width),
            height: min(cropRect.height, imageSize.height)
        )
        
        // Perform the crop
        guard let cgImage = image.cgImage?.cropping(to: clampedCropRect) else {
            // Fallback
            let fallbackImage = resizeImageToCircle(image, to: outputSize)
            onCrop(fallbackImage)
            return
        }
        
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        let finalImage = resizeImageToCircle(croppedImage, to: outputSize)
        
        onCrop(finalImage)
    }
    
    private func resizeImageToCircle(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Create circular clipping path
            context.cgContext.addEllipse(in: rect)
            context.cgContext.clip()
            
            // Draw the image
            image.draw(in: rect)
        }
    }
}

struct CircularCropOverlay: View {
    let cropSize: CGFloat
    let screenSize: CGSize
    
    private var darkOverlayWithCutout: some View {
        ZStack {
            // Dark overlay covering the entire screen
            Color.black.opacity(0.6)
            
            // Clear circle for the crop area
            Circle()
                .frame(width: cropSize, height: cropSize)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
    
    private var borderElements: some View {
        ZStack {
            // Outer border
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 3)
                .frame(width: cropSize, height: cropSize)
            
            // Inner subtle shadow for depth
            Circle()
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                .frame(width: cropSize - 6, height: cropSize - 6)
            
            // Corner indicators for better visual guidance
            cornerIndicators
        }
    }
    
    private var cornerIndicators: some View {
        let positions = [
            CGPoint(x: cropSize / 2 + 10, y: 0),
            CGPoint(x: 0, y: cropSize / 2 + 10),
            CGPoint(x: -(cropSize / 2 + 10), y: 0),
            CGPoint(x: 0, y: -(cropSize / 2 + 10))
        ]
        
        return ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .offset(x: position.x, y: position.y)
                .opacity(0.7)
        }
    }
    
    private var instructionText: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Pan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Pinch to Zoom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.bottom, 50)
        }
    }
    
    var body: some View {
        darkOverlayWithCutout
            .overlay(borderElements)
            .overlay(instructionText)
    }
}

struct AgentInfoView: View {
    let chatbot: Chatbot
    let allUsers: [User]
    let currentUsername: String
    let onLeave: () -> Void
    let onDelete: () -> Void
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    @Environment(\.dismiss) var dismiss

    var creatorUser: User? {
        allUsers.first(where: { $0.username == chatbot.creator })
    }
    var subscriberUsers: [User] {
        allUsers.filter { chatbot.subscribers.contains($0.username) }
    }
    var isCreator: Bool { chatbot.creator == currentUsername }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemGray6),
                        Color(.systemGray5).opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // Header section with icon and name
                        VStack(spacing: 12) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 35, weight: .medium))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: Color.blue.opacity(0.3), radius: 15, x: 0, y: 8)
                            Text(chatbot.name)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 20)

                        // Main info card
                        VStack(alignment: .leading, spacing: 24) {
                            // Creator and created at
                            HStack(spacing: 16) {
                                // Consistent avatar for creator
                                if let creatorUser = creatorUser, let profileImageUrl = creatorUser.profileImageUrl, !profileImageUrl.isEmpty {
                                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                        switch phase {
                                        case .empty:
                                            Circle()
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(ProgressView().scaleEffect(0.6).tint(.blue))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.blue.opacity(0.2), lineWidth: 1))
                                        case .failure(_):
                                            Circle()
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.blue)
                                                )
                                        @unknown default:
                                            Circle()
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.blue)
                                                )
                                        }
                                    }
                                } else if let creatorUser = creatorUser {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(creatorUser.fullname.prefix(1).uppercased())
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.blue)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(.blue)
                                        )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Creator")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    if let creatorUser = creatorUser {
                                        Text(creatorUser.fullname)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                        Text("@\(creatorUser.username)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(chatbot.creator)
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Created")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(chatbot.createdAt, style: .date)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(chatbot.createdAt, style: .time)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Divider()
                            // Subscribers
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("\(subscriberUsers.count)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                VStack(spacing: 6) {
                                    ForEach(subscriberUsers, id: \.id) { user in
                                        HStack(spacing: 8) {
                                            if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(ProgressView().scaleEffect(0.6).tint(.blue))
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 28, height: 28)
                                                            .clipShape(Circle())
                                                            .overlay(Circle().stroke(Color.blue.opacity(0.2), lineWidth: 1))
                                                    case .failure(_):
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.blue)
                                                            )
                                                    @unknown default:
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.blue)
                                                            )
                                                    }
                                                }
                                            } else {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.15))
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Text(user.fullname.prefix(1).uppercased())
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(.blue)
                                                    )
                                            }
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(user.fullname)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.primary)
                                                Text("@\(user.username)")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            Divider()
                            // Schedules
                            if let schedules = chatbot.schedules {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                        Text("Agent Schedules")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.bottom, 8)
                                    VStack(spacing: 0) {
                                        scheduleRow(title: "Availability Message", icon: "calendar.badge.clock", schedule: schedules.availabilityMessageSchedule)
                                        Divider().padding(.leading, 36)
                                        scheduleRow(title: "Suggestions Message", icon: "lightbulb", schedule: schedules.suggestionsSchedule)
                                        Divider().padding(.leading, 36)
                                        scheduleRow(title: "Final Plan Message", icon: "checkmark.seal", schedule: schedules.finalPlanSchedule)
                                    }
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
                        .padding(.horizontal, 20)

                        // Actions
                        VStack(spacing: 12) {
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                            }
                            Button(role: .destructive, action: onLeave) {
                                if isProcessing {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Leave Agent")
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 48)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.systemGray3), lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                            .disabled(isProcessing)
                            if isCreator {
                                Button(role: .destructive, action: onDelete) {
                                    if isProcessing {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("Delete Agent")
                                            .font(.system(size: 18, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: 48)
                                .background(Color(.systemGray5))
                                .foregroundColor(.red)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(.systemGray3), lineWidth: 1)
                                )
                                .buttonStyle(.plain)
                                .disabled(isProcessing)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Agent Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
    }
    private func scheduleRow(title: String, icon: String, schedule: AgentSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 8) {
                    Text(dayString(schedule.dayOfWeek))
                        .font(.system(size: 14, weight: .medium))
                    Text(String(format: "%02d:%02d", schedule.hour, schedule.minute))
                        .font(.system(size: 14, weight: .medium))
                    Text(schedule.timeZone)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
    private func dayString(_ day: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (0...6).contains(day) ? days[day] : "?"
    }
}
