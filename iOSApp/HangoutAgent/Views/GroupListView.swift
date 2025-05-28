import SwiftUI
import FirebaseFirestore

struct GroupListView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedGroup: Group?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()
                
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
                        } else {
                            List {
                                ForEach(vm.groups) { group in
                                    GroupRowWithNavigation(group: group)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .refreshable {
                                await vm.loadGroupsForUser()
                            }
                            .navigationDestination(item: $selectedGroup) { group in
                                GroupChatView(group: group)
                                    .environmentObject(vm)
                            }
                        }
                    } else {
                        Text("No user signed in.")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await vm.loadGroupsForUser()
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await vm.loadGroupsForUser()
                }
            }
        }
    }
}

private struct GroupRow: View {
    let group: Group
    
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
                
                if let lastMessage = group.lastMessage {
                    Text(lastMessage)
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
    let group: Group
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedGroup: Group?
    
    var body: some View {
        HStack {
            Button(action: {
                selectedGroup = group
            }) {
                GroupRow(group: group)
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