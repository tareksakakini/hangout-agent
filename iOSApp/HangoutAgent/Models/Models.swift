//
//  Models.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/26/25.
//

import Foundation

struct Chat: Identifiable, Codable {
    var id: String
    var userID: String
    var chatbotID: String
    var messages: [Message]
}

struct User: Identifiable, Codable {
    var id: String = ""
    var fullname: String = ""
    var username: String = ""
    var email: String = ""
    var password: String = ""
    var subscriptions: [String] = []
    
    func initFromFirestore(userData: [String: Any]) -> User {
        var user = User()
        user.id = userData["uid"] as? String ?? ""
        user.fullname = userData["fullname"] as? String ?? ""
        user.username = userData["username"] as? String ?? ""
        user.email = userData["email"] as? String ?? ""
        user.subscriptions = userData["subscriptions"] as? [String] ?? []
        return user
    }
}

struct Message: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var senderId: String
    var timestamp: Date
    var side: String
    var eventCard: EventCard?
}

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

struct Chatbot: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subscribers: [String]
}

struct Group: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var participants: [String] // User IDs
    var participantNames: [String] // Display names
    var createdAt: Date
    var eventDetails: EventCard?
    var lastMessage: String?
    var updatedAt: Date
}

struct GroupMessage: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var senderId: String
    var senderName: String
    var timestamp: Date
}

struct ParsedAgentResponse {
    let messageToUser: String
    let apiCalls: [ParsedToolCall]
}

struct ParsedToolCall: Codable {
    let function: String
    let arguments: [String: String]
}
