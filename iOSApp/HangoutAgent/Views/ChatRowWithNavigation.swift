//
//  ChatRowWithNavigation.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI

struct ChatRowWithNavigation: View {
    let chatbot: Chatbot
    let user: User
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        HStack {
            NavigationLink(destination: ChatView(user: user, chatbot: chatbot)) {
                ChatRow(chatbot: chatbot)
            }
            .buttonStyle(PlainButtonStyle()) // removes weird tap animation
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await vm.deleteChatbot(chatbotId: chatbot.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
