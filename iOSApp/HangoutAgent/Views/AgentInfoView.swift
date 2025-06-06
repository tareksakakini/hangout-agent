//
//  AgentInfoView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct AgentInfoView: View {
    let chatbot: Chatbot
    let allUsers: [User]
    let currentUsername: String
    let onLeave: () -> Void
    let onDelete: () -> Void
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false

    var creatorUser: User? {
        allUsers.first(where: { $0.username == chatbot.creator })
    }
    var subscriberUsers: [User] {
        allUsers.filter { chatbot.subscribers.contains($0.username) }
    }
    var isCreator: Bool { chatbot.creator == currentUsername }

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
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
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
                                .shadow(color: Color.blue.opacity(0.3), radius: 15, x: 0, y: 8)
                            Text(chatbot.name)
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
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(ProgressView().scaleEffect(0.6).tint(.blue))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.blue.opacity(0.2), lineWidth: 1))
                                        case .failure(_):
                                            Circle()
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.blue)
                                                )
                                        @unknown default:
                                            Circle()
                                                .fill(Color.blue.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text(creatorUser.fullname.prefix(1).uppercased())
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundColor(.blue)
                                                )
                                        }
                                    }
                                } else if let creatorUser = creatorUser {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(creatorUser.fullname.prefix(1).uppercased())
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.blue)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(.blue)
                                        )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Creator")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    if let creatorUser = creatorUser {
                                        Text(creatorUser.fullname)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                        Text("@\(creatorUser.username)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(chatbot.creator)
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Created")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(chatbot.createdAt, style: .date)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(chatbot.createdAt, style: .time)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Divider()
                            // Subscribers
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("\(subscriberUsers.count)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                VStack(spacing: 6) {
                                    ForEach(subscriberUsers, id: \.id) { user in
                                        HStack(spacing: 8) {
                                            if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                                AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(ProgressView().scaleEffect(0.6).tint(.blue))
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 28, height: 28)
                                                            .clipShape(Circle())
                                                            .overlay(Circle().stroke(Color.blue.opacity(0.2), lineWidth: 1))
                                                    case .failure(_):
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.blue)
                                                            )
                                                    @unknown default:
                                                        Circle()
                                                            .fill(Color.blue.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay(
                                                                Text(user.fullname.prefix(1).uppercased())
                                                                    .font(.system(size: 13, weight: .semibold))
                                                                    .foregroundColor(.blue)
                                                            )
                                                    }
                                                }
                                            } else {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.15))
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Text(user.fullname.prefix(1).uppercased())
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(.blue)
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
                            Divider()
                            // Schedules
                            if let schedules = chatbot.schedules {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                        Text("Agent Schedules")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.bottom, 8)
                                    VStack(spacing: 0) {
                                        scheduleRow(title: "Availability Message", icon: "calendar.badge.clock", schedule: schedules.availabilityMessageSchedule)
                                        Divider().padding(.leading, 36)
                                        scheduleRow(title: "Suggestions Message", icon: "lightbulb", schedule: schedules.suggestionsSchedule)
                                        Divider().padding(.leading, 36)
                                        scheduleRow(title: "Final Plan Message", icon: "checkmark.seal", schedule: schedules.finalPlanSchedule)
                                    }
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.top, 4)
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
                                    Text("Leave Agent")
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
                                        Text("Delete Agent")
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
            .navigationTitle("Agent Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
        .confirmationDialog("Are you sure you want to leave this agent?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive) { onLeave() }
        }
        .confirmationDialog("Are you sure you want to delete this agent?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
    private func scheduleRow(title: String, icon: String, schedule: AgentSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 8) {
                    if let specificDate = schedule.specificDate {
                        Text(formatDate(specificDate))
                            .font(.system(size: 14, weight: .medium))
                    } else if let dayOfWeek = schedule.dayOfWeek {
                        Text(dayString(dayOfWeek))
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(String(format: "%02d:%02d", schedule.hour, schedule.minute))
                        .font(.system(size: 14, weight: .medium))
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        
        return dateString
    }
    
    private func dayString(_ day: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (0...6).contains(day) ? days[day] : "?"
    }
}