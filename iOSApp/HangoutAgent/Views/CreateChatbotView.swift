//
//  CreateChatbotView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct CreateChatbotView: View {
    @EnvironmentObject var vm: ViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var name: String = ""
    @State var searchText: String = ""
    @State var selectedUsers: Set<String> = []
    @State var errorMessage: String?
    
    // Scheduling state variables
    @State var availabilityDay: Int = 2 // Default to Tuesday
    @State var availabilityHour: Int = 10 // Default to 10 AM
    @State var availabilityMinute: Int = 0
    
    @State var suggestionsDay: Int = 4 // Default to Thursday
    @State var suggestionsHour: Int = 14 // Default to 2 PM
    @State var suggestionsMinute: Int = 0
    
    @State var finalPlanDay: Int = 5 // Default to Friday
    @State var finalPlanHour: Int = 16 // Default to 4 PM
    @State var finalPlanMinute: Int = 0
    
    @State var timeZone: String = "America/Los_Angeles"
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return []
        } else {
            // Filter out the current user since they'll be added by default
            return vm.users.filter { user in
                let searchLower = searchText.lowercased()
                let matchesSearch = user.username.lowercased().contains(searchLower) || 
                                  user.fullname.lowercased().contains(searchLower)
                let isNotCurrentUser = user.id != vm.signedInUser?.id
                return matchesSearch && isNotCurrentUser
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Modern gradient background
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
                    VStack(spacing: 24) {
                        // Header section
                        VStack(spacing: 16) {
                            // Icon
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
                            
                            VStack(spacing: 8) {
                                Text("Create AI Agent")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("Build your personalized hangout coordinator")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Main form card
                        VStack(spacing: 24) {
                            // Agent name section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "textformat")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Agent Name")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                TextField("Enter agent name...", text: $name)
                                    .font(.system(size: 16, weight: .medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(name.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // Search section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Add Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                    
                                    TextField("Search by name or username...", text: $searchText)
                                        .font(.system(size: 16, weight: .medium))
                                        .textInputAutocapitalization(.never)
                                        .disableAutocorrection(true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(searchText.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                                )
                                
                                // Search results
                                if !filteredUsers.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(filteredUsers) { user in
                                            UserSearchResultView(
                                                user: user,
                                                isSelected: selectedUsers.contains(user.username),
                                                onTap: {
                                                    if selectedUsers.contains(user.username) {
                                                        selectedUsers.remove(user.username)
                                                    } else {
                                                        selectedUsers.insert(user.username)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            
                            // Selected subscribers section
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Selected Subscribers")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(selectedUsers.count + 1)") // +1 for creator
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                
                                // Show creator first
                                if let currentUser = vm.signedInUser {
                                    SelectedUserRowView(
                                        user: currentUser,
                                        isCreator: true,
                                        onRemove: nil
                                    )
                                }
                                
                                // Show selected users
                                ForEach(Array(selectedUsers), id: \.self) { username in
                                    if let user = vm.users.first(where: { $0.username == username }) {
                                        SelectedUserRowView(
                                            user: user,
                                            isCreator: false,
                                            onRemove: {
                                                selectedUsers.remove(username)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(16)
                            
                            // Scheduling section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("Agent Schedule")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                Text("Configure when your agent should send different types of messages")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 16) {
                                    // Availability Messages
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ask for Availability")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $availabilityDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $availabilityHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $availabilityMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Suggestions
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Send Suggestions")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $suggestionsDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $suggestionsHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $suggestionsMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Final Plan
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Send Final Plan")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 12) {
                                            Picker("Day", selection: $finalPlanDay) {
                                                Text("Sunday").tag(0)
                                                Text("Monday").tag(1)
                                                Text("Tuesday").tag(2)
                                                Text("Wednesday").tag(3)
                                                Text("Thursday").tag(4)
                                                Text("Friday").tag(5)
                                                Text("Saturday").tag(6)
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(maxWidth: .infinity)
                                            
                                            HStack(spacing: 4) {
                                                Picker("Hour", selection: $finalPlanHour) {
                                                    ForEach(0..<24) { hour in
                                                        Text(String(format: "%02d", hour)).tag(hour)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                                
                                                Text(":")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Picker("Minute", selection: $finalPlanMinute) {
                                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                                        Text(String(format: "%02d", minute)).tag(minute)
                                                    }
                                                }
                                                .pickerStyle(MenuPickerStyle())
                                                .frame(width: 65)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(16)
                            
                            // Error message
                            if let errorMessage = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
                        .padding(.horizontal, 20)
                        
                        // Create button
                        Button(action: createChatbot) {
                            HStack(spacing: 12) {
                                if name.isEmpty {
                                    Image(systemName: "textformat")
                                        .font(.system(size: 16, weight: .medium))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                Text("Create AI Agent")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: name.isEmpty ? 
                                        [Color.gray.opacity(0.6), Color.gray.opacity(0.4)] :
                                        [Color.blue, Color.blue.opacity(0.8)]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: name.isEmpty ? Color.clear : Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                            .scaleEffect(name.isEmpty ? 1.0 : 1.02)
                            .animation(.easeInOut(duration: 0.2), value: name.isEmpty)
                        }
                        .disabled(name.isEmpty)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            Task {
                vm.users = await vm.getAllUsers()
            }
        }
    }
    
    func createChatbot() {
        Task {
            let chatbotID = UUID().uuidString
            if let user = vm.signedInUser {
                // Always include the creator and selected users
                var subscribers = Array(selectedUsers)
                subscribers.append(user.username)
                
                // Create schedules
                let schedules = ChatbotSchedules(
                    availabilityMessageSchedule: AgentSchedule(
                        dayOfWeek: availabilityDay,
                        hour: availabilityHour,
                        minute: availabilityMinute,
                        timeZone: timeZone
                    ),
                    suggestionsSchedule: AgentSchedule(
                        dayOfWeek: suggestionsDay,
                        hour: suggestionsHour,
                        minute: suggestionsMinute,
                        timeZone: timeZone
                    ),
                    finalPlanSchedule: AgentSchedule(
                        dayOfWeek: finalPlanDay,
                        hour: finalPlanHour,
                        minute: finalPlanMinute,
                        timeZone: timeZone
                    )
                )
                
                await vm.createChatbotButtonPressed(id: chatbotID, name: name, subscribers: subscribers, schedules: schedules, uid: user.id)
                vm.chatbots = await vm.getAllChatbots()
                vm.signedInUser = await vm.getUser(uid: user.id)
                dismiss()
            }
        }
    }
}