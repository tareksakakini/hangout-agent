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
}

struct Chatbot: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subscribers: [String]
}

struct ParsedAgentResponse {
    let messageToUser: String
    let apiCalls: [ParsedToolCall]
}

struct ParsedToolCall: Codable {
    let function: String
    let arguments: [String: String]
}
