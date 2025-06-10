//
//  ChatRow.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//
//


import SwiftUI
import PhotosUI

struct ChatRow: View {
    let chatbot: Chatbot
    let chat: Chat?
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Robot avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "bubbles.and.sparkles.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chatbot.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if let lastMessage = chat?.messages.last {
                        Text(format(timestamp: lastMessage.timestamp))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                if let lastMessage = chat?.messages.last {
                    let senderName = getSenderName(from: lastMessage.senderId)
                    let messagePrefix = senderName.isEmpty ? "" : "\(senderName): "
                    Text("\(messagePrefix)\(lastMessage.text)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                } else {
                    Text("Tap to chat")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private func format(timestamp: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(timestamp) {
            formatter.dateFormat = "h:mm a"
        } else if Calendar.current.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "M/d/yy"
        }
        return formatter.string(from: timestamp)
    }
    
    private func getSenderName(from senderId: String) -> String {
        if senderId == "chatbot" {
            return "Agent"
        }
        if senderId == vm.signedInUser?.id {
            return "You"
        }
        if let user = vm.users.first(where: { $0.id == senderId }) {
            return user.username
        }
        return "Someone"
    }
}
