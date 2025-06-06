//
//  GroupMessage.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct GroupMessage: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var senderId: String
    var senderName: String
    var timestamp: Date
}