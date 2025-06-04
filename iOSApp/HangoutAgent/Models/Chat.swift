//
//  Chat 2.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct Chat: Identifiable, Codable {
    var id: String
    var userID: String
    var chatbotID: String
    var messages: [Message]
}