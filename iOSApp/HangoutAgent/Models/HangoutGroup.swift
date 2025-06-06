//
//  HangoutGroup.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct HangoutGroup: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var participants: [String] // User IDs
    var participantNames: [String] // Display names
    var createdAt: Date
    var eventDetails: EventCard?
    var lastMessage: String?
    var updatedAt: Date
}