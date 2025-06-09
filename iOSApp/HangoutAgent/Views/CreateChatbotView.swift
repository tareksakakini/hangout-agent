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
    private static func defaultDates() -> (suggestionsDate: Date, suggestionsHour: Int, suggestionsMinute: Int, finalPlanDate: Date, finalPlanHour: Int, finalPlanMinute: Int, planningStartDate: Date, planningEndDate: Date) {
        let calendar = Calendar.current
        let now = Date()
        // Suggestions: 2 days from today at 9am
        let suggestionsDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 2, to: now) ?? now) ?? now
        // Final plan: 1 day after suggestions at 9am
        let finalPlanDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: suggestionsDate) ?? suggestionsDate) ?? suggestionsDate
        // Start date: first Friday after final plan
        var startDate = finalPlanDate
        while calendar.component(.weekday, from: startDate) != 6 { // 6 = Friday
            startDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }
        // End date: the Sunday after start date
        var endDate = startDate
        while calendar.component(.weekday, from: endDate) != 1 { // 1 = Sunday
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return (suggestionsDate, 9, 0, finalPlanDate, 9, 0, startDate, endDate)
    }

    @State var suggestionsDate: Date = defaultDates().suggestionsDate
    @State var suggestionsHour: Int = defaultDates().suggestionsHour
    @State var suggestionsMinute: Int = defaultDates().suggestionsMinute
    @State var finalPlanDate: Date = defaultDates().finalPlanDate
    @State var finalPlanHour: Int = defaultDates().finalPlanHour
    @State var finalPlanMinute: Int = defaultDates().finalPlanMinute
    @State var planningStartDate: Date = defaultDates().planningStartDate
    @State var planningEndDate: Date = defaultDates().planningEndDate
    @State var timeZone: String = "America/Los_Angeles"
    
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
                                suggestionsDate: $suggestionsDate,
                                suggestionsHour: $suggestionsHour,
                                suggestionsMinute: $suggestionsMinute,
                                finalPlanDate: $finalPlanDate,
                                finalPlanHour: $finalPlanHour,
                                finalPlanMinute: $finalPlanMinute,
                                timeZone: timeZone,
                                planningStartDate: planningStartDate
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
                await vm.fetchAllUsers()
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
                dismiss()
            }
        }
    }
}