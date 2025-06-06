//
//  Chatbot.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct Chatbot: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subscribers: [String]
    var schedules: ChatbotSchedules?
    var creator: String // username of creator
    var createdAt: Date
    var planningStartDate: Date? // Start of the date range for planning
    var planningEndDate: Date? // End of the date range for planning
}