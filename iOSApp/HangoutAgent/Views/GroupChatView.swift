import SwiftUI
import FirebaseFirestore

struct GroupChatView: View {
    let group: HangoutGroup
    @EnvironmentObject private var vm: ViewModel
    @State private var messageText = ""
    @Environment(\.dismiss) private var dismiss
    @State private var showGroupInfo = false
    @State private var isProcessingGroupAction = false
    @State private var groupActionError: String? = nil
    
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
                .onAppear {
                    // Ensure we start at the bottom when the chat first opens
                    scrollToBottom(using: scrollViewProxy)
                    vm.setActiveGroup(group.id)
                }
                .onChange(of: groupMessages.count) { oldValue, newValue in
                    scrollToBottom(using: scrollViewProxy)
                    vm.markGroupMessagesAsRead(groupId: group.id)
                }
            }
            textbox
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showGroupInfo = true }) {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(
                group: group,
                allUsers: vm.users,
                currentUser: vm.signedInUser,
                onLeave: {
                    Task {
                        isProcessingGroupAction = true
                        groupActionError = nil
                        await vm.leaveGroup(groupId: group.id)
                        DispatchQueue.main.async {
                            showGroupInfo = false
                            dismiss() // Pop back to group list
                        }
                        isProcessingGroupAction = false
                    }
                },
                onDelete: {
                    Task {
                        isProcessingGroupAction = true
                        groupActionError = nil
                        do {
                            await vm.deleteGroup(groupId: group.id)
                            DispatchQueue.main.async {
                                showGroupInfo = false
                                dismiss() // Pop back to group list
                            }
                        } catch {
                            groupActionError = "Failed to delete group. Please try again."
                        }
                        isProcessingGroupAction = false
                    }
                },
                isProcessing: isProcessingGroupAction,
                errorMessage: groupActionError
            )
        }
        .onAppear {
            vm.startListeningToGroupMessages(groupId: group.id)
        }
        .onDisappear {
            vm.stopListeningToGroupMessages(groupId: group.id)
            vm.markGroupMessagesAsRead(groupId: group.id)
            vm.setActiveGroup(nil)
        }
    }
    
    private func scrollToBottom(using proxy: ScrollViewProxy) {
        if let lastMessage = groupMessages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
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

struct GroupInfoView: View {
    let group: HangoutGroup
    let allUsers: [User]
    let currentUser: User?
    let onLeave: () -> Void
    let onDelete: () -> Void
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false

    var creatorUser: User? {
        // Assume the first participant is the creator (if you store creator info, use that)
        guard let firstId = group.participants.first else { return nil }
        return allUsers.first(where: { $0.id == firstId })
    }
    var participantUsers: [User] {
        allUsers.filter { group.participants.contains($0.id) }
    }
    var isCreator: Bool { currentUser?.id == group.participants.first }

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
                                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.7)]),
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
                                .shadow(color: Color.green.opacity(0.3), radius: 15, x: 0, y: 8)
                            Text(group.name)
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
                                                .fill(Color.green.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(ProgressView().scaleEffect(0.6).tint(.green))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.green.opacity(0.2), lineWidth: 1))
                                        case .failure(_):
                                            Circle()
                                                .fill(Color.green.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.green)
                                                )
                                        @unknown default:
                                            Circle()
                                                .fill(Color.green.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.green)
                                                )
                                        }
                                    }
                                } else if let creatorUser = creatorUser {
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(creatorUser.fullname.prefix(1).uppercased())
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.green)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(.green)
                                        )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Creator")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    if let creatorUser = creatorUser {
                                        Text(creatorUser.fullname)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.green)
                                        Text("@\(creatorUser.username)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Unknown")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Created")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(group.createdAt, style: .date)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(group.createdAt, style: .time)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Divider()
                            // Participants
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.green)
                                    Text("Participants")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("\(participantUsers.count)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                VStack(spacing: 6) {
                                    ForEach(participantUsers, id: \.id) { user in
                                        HStack(spacing: 8) {
                                            if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        Circle()
                                                            .fill(Color.green.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(ProgressView().scaleEffect(0.6).tint(.green))
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 28, height: 28)
                                                            .clipShape(Circle())
                                                            .overlay(Circle().stroke(Color.green.opacity(0.2), lineWidth: 1))
                                                    case .failure(_):
                                                        Circle()
                                                            .fill(Color.green.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.green)
                                                            )
                                                    @unknown default:
                                                        Circle()
                                                            .fill(Color.green.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.green)
                                                            )
                                                    }
                                                }
                                            } else {
                                                Circle()
                                                    .fill(Color.green.opacity(0.15))
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Text(user.fullname.prefix(1).uppercased())
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(.green)
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
                            Button(role: .destructive, action: { showLeaveConfirmation = true }) {
                                if isProcessing {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Leave Group")
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
                                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                                    if isProcessing {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("Delete Group")
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
            .navigationTitle("Group Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isProcessing)
                }
            }
            .confirmationDialog("Are you sure you want to leave this group?", isPresented: $showLeaveConfirmation) {
                Button("Leave", role: .destructive) { onLeave() }
            }
            .confirmationDialog("Are you sure you want to delete this group?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

#Preview {
    NavigationView {
        GroupChatView(
            group: HangoutGroup(
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