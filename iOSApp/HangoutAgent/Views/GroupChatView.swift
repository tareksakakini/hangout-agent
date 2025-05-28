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
        VStack {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(groupMessages) { message in
                            GroupMessageBubble(
                                message: message,
                                isCurrentUser: message.senderId == vm.signedInUser?.id
                            )
                        }
                    }
                    .padding()
                }
                .onChange(of: groupMessages.count) { oldValue, newValue in
                    if let lastMessage = groupMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Message input
            HStack {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
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
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        Task {
            await vm.sendGroupMessage(groupId: group.id, text: text)
            messageText = ""
        }
    }
}

struct GroupMessageBubble: View {
    let message: GroupMessage
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                
                Text(message.text)
                    .padding(12)
                    .background(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !isCurrentUser {
                Spacer()
            }
        }
        .id(message.id)
    }
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(timestamp) {
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: timestamp)
        }
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