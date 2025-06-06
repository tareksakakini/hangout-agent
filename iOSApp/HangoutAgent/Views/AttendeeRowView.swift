//
//  AttendeeRowView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct AttendeeRowView: View {
    let attendeeName: String
    @EnvironmentObject private var vm: ViewModel
    
    private var matchedUser: User? {
        // Try to find user by full name first, then by username
        return vm.users.first { user in
            user.fullname.lowercased() == attendeeName.lowercased() ||
            user.username.lowercased() == attendeeName.lowercased()
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture or initials
            if let user = matchedUser,
               let profileImageUrl = user.profileImageUrl,
               !profileImageUrl.isEmpty {
                // Show actual profile picture
                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                    switch phase {
                    case .empty:
                        // Loading state
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.blue)
                            )
                    case .success(let image):
                        // Successfully loaded profile image
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    case .failure(_):
                        // Failed to load - show initials fallback
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(attendeeName.prefix(1).uppercased())
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            )
                    @unknown default:
                        // Default fallback
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(attendeeName.prefix(1).uppercased())
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            )
                    }
                }
            } else {
                // No profile picture available - show initials
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(attendeeName.prefix(1).uppercased())
                            .font(.caption.weight(.medium))
                            .foregroundColor(.blue)
                    )
            }
            
            // Attendee name
            Text(attendeeName)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Online indicator (if user is found in the system)
            if matchedUser != nil {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
    }
}