//
//  TimezoneHelper.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on [Date]
//

import Foundation

class TimezoneHelper {
    /// Get the user's current timezone identifier
    /// Returns a timezone string like "America/New_York" or "Europe/London"
    static func getCurrentTimezone() -> String {
        let timeZone = TimeZone.current
        return timeZone.identifier
    }
    
    /// Get a user-friendly description of the timezone
    static func getTimezoneDescription() -> String {
        let timeZone = TimeZone.current
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.timeStyle = .none
        formatter.dateStyle = .none
        
        let abbreviation = timeZone.localizedName(for: .shortStandard, locale: Locale.current) ?? timeZone.abbreviation() ?? "Unknown"
        let identifier = timeZone.identifier
        
        return "\(identifier) (\(abbreviation))"
    }
    
    /// Validate if a timezone string is valid
    static func isValidTimezone(_ timezoneIdentifier: String) -> Bool {
        return TimeZone(identifier: timezoneIdentifier) != nil
    }
    
    /// Get common timezone identifiers for selection
    static func getCommonTimezones() -> [String] {
        return [
            "America/New_York",      // Eastern Time
            "America/Chicago",       // Central Time
            "America/Denver",        // Mountain Time
            "America/Los_Angeles",   // Pacific Time
            "America/Anchorage",     // Alaska Time
            "Pacific/Honolulu",      // Hawaii Time
            "Europe/London",         // GMT/BST
            "Europe/Paris",          // CET/CEST
            "Europe/Berlin",         // CET/CEST
            "Asia/Tokyo",            // JST
            "Asia/Shanghai",         // CST
            "Asia/Kolkata",          // IST
            "Australia/Sydney",      // AEST/AEDT
            "Australia/Perth",       // AWST
            "America/Toronto",       // Eastern Time (Canada)
            "America/Vancouver",     // Pacific Time (Canada)
        ]
    }
    
    /// Get all available timezone identifiers
    static func getAllTimezones() -> [String] {
        return TimeZone.knownTimeZoneIdentifiers.sorted()
    }
} 