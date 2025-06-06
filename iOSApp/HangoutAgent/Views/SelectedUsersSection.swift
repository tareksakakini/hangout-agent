import SwiftUI

struct SelectedUsersSection: View {
    let currentUser: User?
    let selectedUsers: Set<String>
    let allUsers: [User]
    var onRemove: (String) -> Void
    
    init(currentUser: User?, selectedUsers: Set<String>, allUsers: [User], onRemove: @escaping (String) -> Void) {
        self.currentUser = currentUser
        self.selectedUsers = selectedUsers
        self.allUsers = allUsers
        self.onRemove = onRemove
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Selected Subscribers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(selectedUsers.count + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            if let currentUser = currentUser {
                SelectedUserRowView(user: currentUser, isCreator: true, onRemove: nil)
            }
            ForEach(Array(selectedUsers), id: \.self) { username in
                if let user = allUsers.first(where: { $0.username == username }) {
                    SelectedUserRowView(user: user, isCreator: false, onRemove: { onRemove(username) })
                }
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
    }
} 