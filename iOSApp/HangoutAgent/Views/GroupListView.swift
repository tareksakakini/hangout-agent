import SwiftUI
import FirebaseFirestore

struct GroupListView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedGroup: HangoutGroup?
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                DynamicHeader(
                    title: "Groups",
                    scrollOffset: scrollOffset
                )
                
                ScrollView {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                    }
                    .frame(height: 0)
                    
                    VStack {
                        if vm.signedInUser != nil {
                            if vm.groups.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "person.3")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    
                                    Text("No Groups Yet")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                    
                                    Text("You'll see groups here when you're part of an outing. Groups are automatically created when events are planned!")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else {
                                ForEach(vm.groups) { group in
                                    GroupRowWithNavigation(group: group)
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                }
                                .padding(.top, 10)
                            }
                        } else {
                            Text("No user signed in.")
                                .foregroundColor(.gray)
                                .padding(.top, 100)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
                .refreshable {
                    await vm.loadGroupsForUser()
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct GroupRow: View {
    let group: HangoutGroup
    let lastMessage: GroupMessage?
    
    var body: some View {
        HStack(spacing: 16) {
            // Group avatar circle
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let lastMessage = lastMessage {
                    Text("\(lastMessage.senderName): \(lastMessage.text)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                } else if let lastMessageText = group.lastMessage {
                    Text(lastMessageText)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .italic()
                }
                
                Text("\(group.participantNames.count) participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTimestamp(group.updatedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }
}

private struct GroupRowWithNavigation: View {
    let group: HangoutGroup
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedGroup: HangoutGroup?
    
    var body: some View {
        let lastMessage = vm.groupMessages[group.id]?.last
        HStack {
            Button(action: {
                selectedGroup = group
            }) {
                GroupRow(group: group, lastMessage: lastMessage)
            }
            .buttonStyle(PlainButtonStyle()) // removes weird tap animation
        }
        .navigationDestination(item: $selectedGroup) { group in
            GroupChatView(group: group)
                .environmentObject(vm)
        }
    }
}

#Preview {
    GroupListView()
        .environmentObject(ViewModel())
} 