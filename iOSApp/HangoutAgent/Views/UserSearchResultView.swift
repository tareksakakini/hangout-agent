//
//  UserSearchResultView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct UserSearchResultView: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    let onViewProfile: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture (tappable for profile)
            Group {
                if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.blue)
                                )
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                        case .failure(_):
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(user.fullname.prefix(1).uppercased())
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.blue)
                                )
                        @unknown default:
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(user.fullname.prefix(1).uppercased())
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.blue)
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(user.fullname.prefix(1).uppercased())
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.blue)
                        )
                }
            }
            .onTapGesture {
                onViewProfile()
            }
            // Rest of row (select/deselect)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullname)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("@\(user.username)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}