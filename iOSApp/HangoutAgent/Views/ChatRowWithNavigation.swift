//
//  ChatRowWithNavigation.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct ChatRowWithNavigation: View {
    let chatbot: Chatbot
    let user: User
    let chat: Chat?
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        HStack {
            NavigationLink(destination: ChatView(user: user, chatbot: chatbot)) {
                ChatRow(chatbot: chatbot, chat: chat)
            }
            .buttonStyle(PlainButtonStyle()) // removes weird tap animation
        }
        // Removed swipeActions for delete
    }
}
