//
//  ParsedToolCall.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct ParsedToolCall: Codable {
    let function: String
    let arguments: [String: String]
}