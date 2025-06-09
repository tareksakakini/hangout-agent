//
//  HomeView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var selectedTab = 0
    @State private var showCreateChatbot = false
    
    var body: some View {
        if vm.signedInUser != nil {
            NavigationStack {
                TabView(selection: $selectedTab) {
                    ChatListView(showCreateChatbot: $showCreateChatbot)
                        .tabItem {
                            Image(systemName: "message")
                            Text("Chats")
                        }
                        .tag(0)
                    
                    GroupListView()
                        .tabItem {
                            Image(systemName: "person.3")
                            Text("Groups")
                        }
                        .tag(1)
                    
                    ProfileView()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                        .tag(2)
                }
                .navigationTitle(selectedTab == 0 ? "Chats" : selectedTab == 1 ? "Groups" : "Profile")
                .toolbar {
                    if selectedTab == 0 {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showCreateChatbot = true
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showCreateChatbot) {
                    CreateChatbotView()
                }
            }
        } else {
            Text("Please sign in to continue")
                .foregroundColor(.gray)
        }
    }
}