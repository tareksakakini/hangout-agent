import SwiftUI
import FirebaseFirestore

struct GroupListView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedGroup: Group?
    @State private var showingCreateGroup = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Debug info
                if let user = vm.signedInUser {
                    Text("Signed in as: \(user.fullname)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Text("Groups loaded: \(vm.groups.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                if vm.groups.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.3")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Groups Yet")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Create a group to start chatting with multiple people")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Create Group") {
                            showingCreateGroup = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.groups) { group in
                            GroupRowView(group: group)
                                .onTapGesture {
                                    selectedGroup = group
                                }
                        }
                    }
                    .refreshable {
                        await vm.loadGroupsForUser()
                    }
                    .navigationDestination(item: $selectedGroup) { group in
                        GroupChatView(group: group)
                            .environmentObject(vm)
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") {
                        Task {
                            await vm.loadGroupsForUser()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New Group") {
                        showingCreateGroup = true
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
                    .environmentObject(vm)
            }
            .onAppear {
                Task {
                    await vm.loadGroupsForUser()
                }
            }
        }
    }
}

struct GroupRowView: View {
    let group: Group
    
    var body: some View {
        HStack {
            // Group icon
            Image(systemName: "person.3.fill")
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let lastMessage = group.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Text("\(group.participantNames.count) participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack {
                Text(formatTimestamp(group.updatedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct CreateGroupView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Group Name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createGroup() {
        guard !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        
        Task {
            let success = await vm.createGroup(name: groupName.trimmingCharacters(in: .whitespacesAndNewlines))
            
            await MainActor.run {
                isCreating = false
                if success {
                    dismiss()
                } else {
                    // Could add error handling here
                    print("Failed to create group")
                }
            }
        }
    }
}

#Preview {
    GroupListView()
        .environmentObject(ViewModel())
} 