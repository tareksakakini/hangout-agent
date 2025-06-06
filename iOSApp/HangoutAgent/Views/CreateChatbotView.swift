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
    
    // Scheduling state variables - now using dates instead of days
    @State var availabilityDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State var availabilityHour: Int = 10 // Default to 10 AM
    @State var availabilityMinute: Int = 0
    
    @State var suggestionsDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State var suggestionsHour: Int = 14 // Default to 2 PM
    @State var suggestionsMinute: Int = 0
    
    @State var finalPlanDate: Date = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
    @State var finalPlanHour: Int = 16 // Default to 4 PM
    @State var finalPlanMinute: Int = 0
    
    @State var timeZone: String = "America/Los_Angeles"
    
    // Date range for planning
    @State var planningStartDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State var planningEndDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    
    @State private var profileUser: User? = nil
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return []
        } else {
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
                        HeaderSection()
                        
                        // Main form card
                        VStack(spacing: 24) {
                            // Agent name section
                            NameInputSection(name: $name)
                            
                            // Search section
                            SearchSection(
                                searchText: $searchText,
                                filteredUsers: filteredUsers,
                                selectedUsers: selectedUsers,
                                onSelect: { user in
                                    if selectedUsers.contains(user.username) {
                                        selectedUsers.remove(user.username)
                                    } else {
                                        selectedUsers.insert(user.username)
                                    }
                                },
                                onViewProfile: { user in
                                    profileUser = user
                                }
                            )
                            
                            // Selected subscribers section
                            SelectedUsersSection(
                                currentUser: vm.signedInUser,
                                selectedUsers: selectedUsers,
                                allUsers: vm.users,
                                onRemove: { username in
                                    selectedUsers.remove(username)
                                }
                            )
                            
                            // Date range section
                            DateRangeSection(
                                planningStartDate: $planningStartDate,
                                planningEndDate: $planningEndDate
                            )
                            
                            // Scheduling section
                            SchedulingSection(
                                availabilityDate: $availabilityDate,
                                availabilityHour: $availabilityHour,
                                availabilityMinute: $availabilityMinute,
                                suggestionsDate: $suggestionsDate,
                                suggestionsHour: $suggestionsHour,
                                suggestionsMinute: $suggestionsMinute,
                                finalPlanDate: $finalPlanDate,
                                finalPlanHour: $finalPlanHour,
                                finalPlanMinute: $finalPlanMinute,
                                timeZone: timeZone
                            )
                            
                            // Error message
                            ErrorMessageSection(errorMessage: errorMessage)
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
                        .padding(.horizontal, 20)
                        
                        // Create button
                        CreateButtonSection(name: name, action: createChatbot)
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
        .sheet(item: $profileUser) { user in
            NavigationView {
                ProfileView(user: user)
                    .environmentObject(vm)
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
                
                // Helper function to format date as YYYY-MM-DD
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                // Create schedules with specific dates
                let schedules = ChatbotSchedules(
                    availabilityMessageSchedule: AgentSchedule(
                        dayOfWeek: nil,
                        specificDate: dateFormatter.string(from: availabilityDate),
                        hour: availabilityHour,
                        minute: availabilityMinute,
                        timeZone: timeZone
                    ),
                    suggestionsSchedule: AgentSchedule(
                        dayOfWeek: nil,
                        specificDate: dateFormatter.string(from: suggestionsDate),
                        hour: suggestionsHour,
                        minute: suggestionsMinute,
                        timeZone: timeZone
                    ),
                    finalPlanSchedule: AgentSchedule(
                        dayOfWeek: nil,
                        specificDate: dateFormatter.string(from: finalPlanDate),
                        hour: finalPlanHour,
                        minute: finalPlanMinute,
                        timeZone: timeZone
                    )
                )
                
                await vm.createChatbotButtonPressed(id: chatbotID, name: name, subscribers: subscribers, schedules: schedules, uid: user.id, planningStartDate: planningStartDate, planningEndDate: planningEndDate)
                vm.chatbots = await vm.getAllChatbots()
                vm.signedInUser = await vm.getUser(uid: user.id)
                dismiss()
            }
        }
    }
}