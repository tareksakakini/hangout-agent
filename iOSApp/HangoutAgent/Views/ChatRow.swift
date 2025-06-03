//
//  ChatRow.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI

struct ChatRow: View {
    let chatbot: Chatbot
    
    var body: some View {
        HStack(spacing: 16) {
            // Placeholder circle avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(chatbot.name.prefix(1))
                        .font(.title2.bold())
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(chatbot.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Tap to chat")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

