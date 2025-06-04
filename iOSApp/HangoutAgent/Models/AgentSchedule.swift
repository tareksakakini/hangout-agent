//
//  AgentSchedule.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct AgentSchedule: Codable, Hashable {
    var dayOfWeek: Int // 0 = Sunday, 1 = Monday, etc.
    var hour: Int // 0-23
    var minute: Int // 0-59
    var timeZone: String // e.g., "America/Los_Angeles"
    
    // Convert to cron format for Firebase Functions
    var cronExpression: String {
        return "\(minute) \(hour) * * \(dayOfWeek)"
    }
}