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
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                DynamicHeader(
                    title: "Chats",
                    scrollOffset: scrollOffset,
                    rightButton: {
                        AnyView(
                            Button(action: { showCreateChatbot = true }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                            }
                        )
                    }
                )
                
                ScrollView {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                    }
                    .frame(height: 0)
                    
                    VStack {
                        if let user = vm.signedInUser {
                            let userChatbots = vm.chatbots.filter { user.subscriptions.contains($0.id) }
                            if userChatbots.isEmpty {
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
                                .padding(.top, 100)
                            } else {
                                ForEach(userChatbots) { chatbot in
                                    ChatRowWithNavigation(chatbot: chatbot, user: user)
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                }
                                .padding(.top, 10)
                            }
                        } else {
                            Text("No user signed in.")
                                .foregroundColor(.gray)
                                .padding(.top, 100)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
                .refreshable {
                    await vm.loadSignedInUser()
                    await vm.fetchAllChatbots()
                }
            }
        }
        .navigationBarHidden(true)
    }
}