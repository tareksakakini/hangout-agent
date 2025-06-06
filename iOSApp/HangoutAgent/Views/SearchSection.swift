import SwiftUI

struct SearchSection: View {
    @Binding var searchText: String
    var filteredUsers: [User]
    var selectedUsers: Set<String>
    var onSelect: (User) -> Void
    var onViewProfile: (User) -> Void
    
    init(searchText: Binding<String>, filteredUsers: [User], selectedUsers: Set<String>, onSelect: @escaping (User) -> Void, onViewProfile: @escaping (User) -> Void) {
        self._searchText = searchText
        self.filteredUsers = filteredUsers
        self.selectedUsers = selectedUsers
        self.onSelect = onSelect
        self.onViewProfile = onViewProfile
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Add Subscribers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                TextField("Search by name or username...", text: $searchText)
                    .font(.system(size: 16, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(searchText.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
            )
            if !filteredUsers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(filteredUsers) { user in
                        UserSearchResultView(
                            user: user,
                            isSelected: selectedUsers.contains(user.username),
                            onTap: { onSelect(user) },
                            onViewProfile: { onViewProfile(user) }
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }
} 