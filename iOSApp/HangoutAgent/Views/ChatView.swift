import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var vm: ViewModel
    
    @State var user: User
    @State var chatbot: Chatbot
    var chat: Chat? {
        vm.chats.first(where: { $0.userID == user.id && $0.chatbotID == chatbot.id })
    }
    
    @State var messageText: String = ""
    
    var body: some View {
        NavigationStack {
            Divider().padding(.top, 10)
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    if let chat {
                        ForEach(chat.messages, id: \.id) { message in
                            MessageView(
                                text: message.text,
                                alignment: message.side == "user" ? .trailing : .leading,
                                timestamp: message.timestamp
                            )
                            .id(message.id)
                        }
                    }
                }
                .onChange(of: chat?.messages.count) { _ in
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
        .onDisappear {
            if let chat = chat {
                vm.stopListeningToMessages(chatId: chat.id)
            }
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
                    List {
                        ForEach(vm.chatbots) { chatbot in
                            if user.subscriptions.contains(chatbot.id) {
                                ChatRowWithNavigation(chatbot: chatbot, user: user)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await vm.deleteChatbot(chatbotId: chatbot.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct CreateChatbotView: View {
    @EnvironmentObject var vm: ViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var name: String = ""
    @State var searchText: String = ""
    @State var selectedUsers: Set<String> = []
    @State var errorMessage: String?
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return []
        } else {
            return vm.users.filter { $0.username.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    TextField("Chatbot Name", text: $name)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                    
                    TextField("Search Users...", text: $searchText)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    if !filteredUsers.isEmpty {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(filteredUsers) { user in
                                    HStack {
                                        Text(user.username)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Button(action: {
                                            addSubscriber(username: user.username)
                                        }) {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(10)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(20)
                .shadow(radius: 10)
                .padding(.horizontal)
                
                if !selectedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Subscribers")
                            .font(.headline)
                            .padding(.bottom, 8)
                        
                        ForEach(Array(selectedUsers), id: \.self) { username in
                            HStack {
                                Text(username)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: {
                                    removeSubscriber(username: username)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .padding(.horizontal)
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
                
                Button(action: createChatbot) {
                    Text("Create Chatbot")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.isEmpty || selectedUsers.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
                .disabled(name.isEmpty || selectedUsers.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
        }
        .navigationTitle("Create Chatbot")
        .onAppear {
            Task {
                vm.users = await vm.getAllUsers()
            }
        }
    }
    
    func addSubscriber(username: String) {
        selectedUsers.insert(username)
        searchText = ""
    }
    
    func removeSubscriber(username: String) {
        selectedUsers.remove(username)
    }
    
    func createChatbot() {
        Task {
            let chatbotID = UUID().uuidString
            if let user = vm.signedInUser {
                var subscribers = Array(selectedUsers)
                if !subscribers.contains(user.username) {
                    subscribers.append(user.username)
                }
                await vm.createChatbotButtonPressed(id: chatbotID, name: name, subscribers: subscribers, uid: user.id)
                vm.chatbots = await vm.getAllChatbots()
                vm.signedInUser = await vm.getUser(uid: user.id)
                dismiss()
            }
        }
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
                    
                    ProfileView()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                        .tag(1)
                }
                .navigationTitle(selectedTab == 0 ? "Chats" : "Profile")
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

struct LoginView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var email: String = ""
    @State var password: String = ""
    @State var showWrongMessage: Bool = false
    @State var goToNextScreen: Bool = false
    @State var isPasswordVisible = false
    @State var isVerified = false
    @State var wrongMessage: String = " "
    
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
                
                Spacer()
            }
            .padding()
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
            Group {
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
                goToNextScreen = true
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
        .navigationDestination(isPresented: $goToNextScreen) {
            if vm.signedInUser != nil {
                HomeView()
            }
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
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Button(action: {
                Task {
                    await vm.signoutButtonPressed()
                    dismiss()
                }
            }) {
                Text("Sign Out")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Button(action: {
                Task {
                    await vm.deleteAccountButtonPressed()
                    dismiss()
                }
            }) {
                Text("Delete Account")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Profile")
    }
}

struct SignupView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var fullname: String = ""
    @State var username: String = ""
    @State var email: String = ""
    @State var password: String = ""
    @State var goToNextScreen: Bool = false
    @State var isPasswordVisible = false
    @State var user: User? = nil
    
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
    
    private var PasswordField: some View {
        HStack {
            Group {
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
                if let signedUpUser = await vm.signupButtonPressed(fullname: fullname, username: username, email: email, password: password) {
                    DispatchQueue.main.async {
                        vm.signedInUser = signedUpUser
                        dismiss()
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
            if let _ = vm.signedInUser {
                // User is signed in -> go to ChatListView
                HomeView()
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
