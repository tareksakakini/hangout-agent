import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject private var vm: ViewModel
    
    @State var user: User
    @State var chatbot: Chatbot
    var chat: Chat? {
        vm.chats.first { chat in
            chat.userID == user.id && chat.chatbotID == chatbot.id
        }
    }
    
    @State var messageText: String = ""
    
    var body: some View {
        NavigationStack {
            Divider().padding(.top, 10)
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    if let chat {
                        VStack(spacing: 12) {
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
