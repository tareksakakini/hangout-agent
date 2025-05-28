import SwiftUI
import FirebaseFirestore

struct GroupChatView: View {
    let group: Group
    @EnvironmentObject private var vm: ViewModel
    @State private var messageText = ""
    @State private var showEventDetails = false
    
    private var groupMessages: [GroupMessage] {
        vm.groupMessages[group.id] ?? []
    }
    
    var body: some View {
        NavigationStack {
            Divider().padding(.top, 10)
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(groupMessages) { message in
                            GroupMessageView(
                                message: message,
                                isCurrentUser: message.senderId == vm.signedInUser?.id
                            )
                            .id(message.id)
                        }
                    }
                }
                .onChange(of: groupMessages.count) { oldValue, newValue in
                    scrollToBottom(using: scrollViewProxy)
                }
            }
            textbox
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if group.eventDetails != nil {
                        Button("View Event Details") {
                            showEventDetails = true
                        }
                    }
                    
                    Button("Group Info") {
                        // TODO: Show group info
                    }
                    
                    Button("Leave Group", role: .destructive) {
                        Task {
                            await vm.leaveGroup(groupId: group.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEventDetails) {
            if let eventDetails = group.eventDetails {
                NavigationView {
                    EventCardView(eventCard: eventDetails)
                        .navigationTitle("Event Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showEventDetails = false
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            vm.startListeningToGroupMessages(groupId: group.id)
        }
        .onDisappear {
            vm.stopListeningToGroupMessages(groupId: group.id)
        }
    }
    
    private func scrollToBottom(using proxy: ScrollViewProxy) {
        if let lastMessage = groupMessages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        // Store the message text and clear the field immediately
        let currentMessage = messageText
        messageText = ""
        
        Task {
            await vm.sendGroupMessage(groupId: group.id, text: currentMessage)
        }
    }
}

extension GroupChatView {
    private var textbox: some View {
        HStack {
            TextField("Type a message...", text: $messageText)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            Button(action: sendMessage) {
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

struct GroupMessageView: View {
    let message: GroupMessage
    let isCurrentUser: Bool
    
    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
            if !isCurrentUser {
                Text(message.senderName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            Text(message.text)
                .padding()
                .background(isCurrentUser ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            
            Text(formatTimestamp(message.timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: UIScreen.main.bounds.width / 2, alignment: isCurrentUser ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.horizontal)
    }
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

#Preview {
    NavigationView {
        GroupChatView(
            group: Group(
                id: "preview",
                name: "Preview Group",
                participants: ["user1", "user2"],
                participantNames: ["User 1", "User 2"],
                createdAt: Date(),
                eventDetails: nil,
                lastMessage: nil,
                updatedAt: Date()
            )
        )
        .environmentObject(ViewModel())
    }
} 