//
//  ParsedAgentResponse.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct ParsedAgentResponse {
    let messageToUser: String
    let apiCalls: [ParsedToolCall]
}