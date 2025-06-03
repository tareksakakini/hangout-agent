//
//  Chatbot.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//


import Foundation

struct Chatbot: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subscribers: [String]
}