import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject private var vm: ViewModel
    
    @State var user: User
    @State var chatbot: Chatbot
    var chat: Chat? {
        vm.chats.first(where: { $0.userID == user.id && $0.chatbotID == chatbot.id })
    }
    
    @State var messageText: String = ""
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadResult: (success: Bool, message: String)? = nil
    @State private var showUploadResult = false
    @State private var imageRefreshId = UUID()
    @State private var isRemovingImage = false
    @State private var showPhotoActionSheet = false
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?
    @State private var showImageCrop = false
    
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showPhotoActionSheet = true
                }) {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.blue)
                }
            }
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
                if let signedUpUser = await vm.signupButtonPressed(fullname: fullname, username: username, email: email, password: password) {
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
                
                // Add to calendar button
                Button(action: {
                    // TODO: Implement add to calendar functionality
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Add to Calendar")
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
    
    @State private var currentOffset = CGSize.zero
    @State private var finalOffset = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    // Image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: finalOffset.width + currentOffset.width, 
                               y: finalOffset.height + currentOffset.height)
                        .gesture(
                            SimultaneousGesture(
                                // Pan gesture
                                DragGesture()
                                    .onChanged { value in
                                        currentOffset = value.translation
                                    }
                                    .onEnded { value in
                                        finalOffset.width += value.translation.width
                                        finalOffset.height += value.translation.height
                                        currentOffset = .zero
                                    },
                                // Pinch gesture for zoom
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = finalScale * value
                                        scale = min(max(scale, 0.5), 3.0)
                                    }
                                    .onEnded { value in
                                        finalScale = scale
                                    }
                            )
                        )
                    
                    // Crop overlay - with allowsHitTesting(false) to not block touches
                    CropOverlayView(geometry: geometry)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropImage()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func cropImage() {
        // Calculate the crop area based on user's pan and zoom
        let cropAreaSize: CGFloat = 300 // The size of our crop overlay
        let imageSize = image.size
        
        // Calculate the actual crop rectangle in the image's coordinate system
        let imageAspectRatio = imageSize.width / imageSize.height
        let displayImageSize: CGSize
        
        // Determine how the image is displayed (fit aspect ratio)
        if imageAspectRatio > 1 {
            // Landscape image
            displayImageSize = CGSize(width: cropAreaSize * imageAspectRatio, height: cropAreaSize)
        } else {
            // Portrait image  
            displayImageSize = CGSize(width: cropAreaSize, height: cropAreaSize / imageAspectRatio)
        }
        
        // Apply the scale factor
        let scaledDisplaySize = CGSize(
            width: displayImageSize.width * scale,
            height: displayImageSize.height * scale
        )
        
        // Calculate the center point of the crop area
        let cropCenterX = cropAreaSize / 2
        let cropCenterY = cropAreaSize / 2
        
        // Account for the user's pan offset
        let totalOffsetX = finalOffset.width + currentOffset.width
        let totalOffsetY = finalOffset.height + currentOffset.height
        
        // Calculate the crop rectangle in the scaled image's coordinate system
        let cropRect = CGRect(
            x: (scaledDisplaySize.width / 2) - cropCenterX - totalOffsetX,
            y: (scaledDisplaySize.height / 2) - cropCenterY - totalOffsetY,
            width: cropAreaSize,
            height: cropAreaSize
        )
        
        // Convert to original image coordinates
        let scaleToOriginal = max(imageSize.width / scaledDisplaySize.width, imageSize.height / scaledDisplaySize.height)
        let originalCropRect = CGRect(
            x: cropRect.origin.x * scaleToOriginal,
            y: cropRect.origin.y * scaleToOriginal,
            width: cropRect.width * scaleToOriginal,
            height: cropRect.height * scaleToOriginal
        )
        
        // Ensure the crop rect is within image bounds
        let clampedCropRect = CGRect(
            x: max(0, min(originalCropRect.origin.x, imageSize.width - originalCropRect.width)),
            y: max(0, min(originalCropRect.origin.y, imageSize.height - originalCropRect.height)),
            width: min(originalCropRect.width, imageSize.width),
            height: min(originalCropRect.height, imageSize.height)
        )
        
        // Perform the actual crop
        guard let cgImage = image.cgImage?.cropping(to: clampedCropRect) else {
            // Fallback to resizing if cropping fails
            let resizedImage = resizeImage(image, to: CGSize(width: 400, height: 400))
            onCrop(resizedImage)
            return
        }
        
        let croppedUIImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Resize the cropped image to final size
        let finalImage = resizeImage(croppedUIImage, to: CGSize(width: 400, height: 400))
        onCrop(finalImage)
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct CropOverlayView: View {
    let geometry: GeometryProxy
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.5)
            
            // Crop area (clear rectangle in the center)
            Rectangle()
                .frame(width: min(geometry.size.width - 40, 300), 
                      height: min(geometry.size.width - 40, 300))
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay(
            // Crop border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: min(geometry.size.width - 40, 300), 
                      height: min(geometry.size.width - 40, 300))
        )
    }
}
