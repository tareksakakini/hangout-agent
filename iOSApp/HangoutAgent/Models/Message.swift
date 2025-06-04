//
//  Message.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct Message: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var senderId: String
    var timestamp: Date
    var side: String
    var eventCard: EventCard?
}