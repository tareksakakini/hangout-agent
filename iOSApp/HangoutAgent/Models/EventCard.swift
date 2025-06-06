//
//  EventCard.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct EventCard: Identifiable, Codable, Equatable, Hashable {
    var type: String
    var activity: String
    var location: String
    var date: String
    var startTime: String
    var endTime: String
    var description: String
    var imageUrl: String
    var attendees: [String]?
    
    var id: String {
        // Generate a unique ID based on activity and date
        return "\(activity)-\(date)".replacingOccurrences(of: " ", with: "-")
    }
}