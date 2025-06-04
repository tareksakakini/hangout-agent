//
//  ChatbotSchedules.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct ChatbotSchedules: Codable, Hashable {
    var availabilityMessageSchedule: AgentSchedule
    var suggestionsSchedule: AgentSchedule  
    var finalPlanSchedule: AgentSchedule
}