//
//  AgentSchedule.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//

import Foundation

struct AgentSchedule: Codable, Hashable {
    var dayOfWeek: Int? // 0 = Sunday, 1 = Monday, etc. (optional for backward compatibility)
    var specificDate: String? // YYYY-MM-DD format for exact date scheduling
    var hour: Int // 0-23
    var minute: Int // 0-59
    var timeZone: String // e.g., "America/Los_Angeles"
    
    // Convert to cron format for Firebase Functions
    var cronExpression: String {
        if let specificDate = specificDate {
            // For specific dates, we'll handle this in the Firebase function
            // Return a placeholder that indicates date-based scheduling
            return "date:\(specificDate) \(minute) \(hour)"
        } else if let dayOfWeek = dayOfWeek {
            // Legacy day-of-week format
            return "\(minute) \(hour) * * \(dayOfWeek)"
        } else {
            // Fallback
            return "\(minute) \(hour) * * 0"
        }
    }
    
    // Check if this schedule should run on a specific date
    func shouldRunOn(date: Date, in timeZone: TimeZone) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        let dateString = formatter.string(from: date)
        
        if let specificDate = specificDate {
            return dateString == specificDate
        } else if let dayOfWeek = dayOfWeek {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: timeZone, from: date)
            let currentDayOfWeek = components.weekday! - 1 // Convert to 0-6 format
            return currentDayOfWeek == dayOfWeek
        }
        
        return false
    }
    
    // Check if this schedule should run at a specific time
    func shouldRunAt(hour: Int, minute: Int) -> Bool {
        return self.hour == hour && self.minute == minute
    }
}