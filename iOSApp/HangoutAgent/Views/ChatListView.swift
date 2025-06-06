//
//  ChatListView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct ChatListView: View {
    @EnvironmentObject private var vm: ViewModel
    @Binding var showCreateChatbot: Bool
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack {
                if let user = vm.signedInUser {
                    let userChatbots = vm.chatbots.filter { user.subscriptions.contains($0.id) }
                    if userChatbots.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "message")
                                .font(.system(size: 60))
                                .foregroundColor(.blue.opacity(0.4))
                            Text("No AI Agents Yet")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("You haven't created or joined any AI agents yet. Agents help you coordinate hangouts and automate planning with friends!")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button(action: { showCreateChatbot = true }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Create AI Agent")
                                }
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(radius: 4)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Spacer()
                    } else {
                        List {
                            ForEach(userChatbots) { chatbot in
                                ChatRowWithNavigation(chatbot: chatbot, user: user)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    Text("No user signed in.")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}