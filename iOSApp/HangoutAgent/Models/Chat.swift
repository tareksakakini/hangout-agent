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
