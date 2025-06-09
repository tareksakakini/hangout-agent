import SwiftUI

struct SchedulingSection: View {
    @Binding var suggestionsDate: Date
    @Binding var suggestionsHour: Int
    @Binding var suggestionsMinute: Int
    @Binding var finalPlanDate: Date
    @Binding var finalPlanHour: Int
    @Binding var finalPlanMinute: Int
    var timeZone: String
    var planningStartDate: Date
    
    init(
        suggestionsDate: Binding<Date>,
        suggestionsHour: Binding<Int>,
        suggestionsMinute: Binding<Int>,
        finalPlanDate: Binding<Date>,
        finalPlanHour: Binding<Int>,
        finalPlanMinute: Binding<Int>,
        timeZone: String,
        planningStartDate: Date
    ) {
        self._suggestionsDate = suggestionsDate
        self._suggestionsHour = suggestionsHour
        self._suggestionsMinute = suggestionsMinute
        self._finalPlanDate = finalPlanDate
        self._finalPlanHour = finalPlanHour
        self._finalPlanMinute = finalPlanMinute
        self.timeZone = timeZone
        self.planningStartDate = planningStartDate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Agent Schedule")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("Configure specific dates and times when your agent should send different types of messages")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(nil)
            
            // Schedule items
            VStack(spacing: 12) {
                SchedulingPickerRow(
                    title: "Send Suggestions",
                    icon: "lightbulb.fill",
                    iconColor: .orange,
                    date: $suggestionsDate,
                    hour: $suggestionsHour,
                    minute: $suggestionsMinute,
                    minDate: Date(),
                    maxDate: Calendar.current.date(byAdding: .day, value: -1, to: planningStartDate) ?? planningStartDate,
                    maxHour: nil,
                    maxMinute: nil
                )
                
                SchedulingPickerRow(
                    title: "Send Final Plan",
                    icon: "checkmark.seal.fill",
                    iconColor: .blue,
                    date: $finalPlanDate,
                    hour: $finalPlanHour,
                    minute: $finalPlanMinute,
                    minDate: suggestionsDate,
                    maxDate: Calendar.current.date(byAdding: .day, value: -1, to: planningStartDate) ?? planningStartDate,
                    minHour: Calendar.current.isDate(suggestionsDate, inSameDayAs: finalPlanDate) ? suggestionsHour : nil,
                    minMinute: Calendar.current.isDate(suggestionsDate, inSameDayAs: finalPlanDate) ? suggestionsMinute : nil
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .onChange(of: finalPlanDate) { _, _ in
            // If suggestionsDate == finalPlanDate and suggestions time is after final plan, auto-correct
            if Calendar.current.isDate(suggestionsDate, inSameDayAs: finalPlanDate) {
                if suggestionsHour > finalPlanHour || (suggestionsHour == finalPlanHour && suggestionsMinute > finalPlanMinute) {
                    setFinalPlanTimeToTwoHoursAfterSuggestions()
                }
            }
            // If finalPlanDate is before suggestionsDate, auto-correct to suggestionsDate and set time 2 hours after suggestions
            if finalPlanDate < suggestionsDate {
                finalPlanDate = suggestionsDate
                setFinalPlanTimeToTwoHoursAfterSuggestions()
            }
        }
        .onChange(of: finalPlanHour) { _, _ in
            if Calendar.current.isDate(suggestionsDate, inSameDayAs: finalPlanDate) {
                if finalPlanHour < suggestionsHour || (finalPlanHour == suggestionsHour && finalPlanMinute <= suggestionsMinute) {
                    setFinalPlanTimeToTwoHoursAfterSuggestions()
                }
            }
            if finalPlanDate < suggestionsDate {
                finalPlanDate = suggestionsDate
                setFinalPlanTimeToTwoHoursAfterSuggestions()
            }
        }
        .onChange(of: finalPlanMinute) { _, _ in
            if Calendar.current.isDate(suggestionsDate, inSameDayAs: finalPlanDate) {
                if finalPlanHour < suggestionsHour || (finalPlanHour == suggestionsHour && finalPlanMinute <= suggestionsMinute) {
                    setFinalPlanTimeToTwoHoursAfterSuggestions()
                }
            }
            if finalPlanDate < suggestionsDate {
                finalPlanDate = suggestionsDate
                setFinalPlanTimeToTwoHoursAfterSuggestions()
            }
        }
    }

    private func setFinalPlanTimeToTwoHoursAfterSuggestions() {
        var newHour = suggestionsHour + 2
        var newMinute = suggestionsMinute
        if newHour > 23 || (newHour == 23 && newMinute > 55) {
            finalPlanHour = 23
            finalPlanMinute = 55
        } else {
            finalPlanHour = newHour
            finalPlanMinute = newMinute
        }
    }
}

struct SchedulingPickerRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var date: Date
    @Binding var hour: Int
    @Binding var minute: Int
    var minDate: Date
    var maxDate: Date
    var minHour: Int?
    var minMinute: Int?
    var maxHour: Int?
    var maxMinute: Int?
    
    init(title: String, icon: String, iconColor: Color, date: Binding<Date>, hour: Binding<Int>, minute: Binding<Int>, minDate: Date, maxDate: Date, minHour: Int? = nil, minMinute: Int? = nil, maxHour: Int? = nil, maxMinute: Int? = nil) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._date = date
        self._hour = hour
        self._minute = minute
        self.minDate = minDate
        self.maxDate = maxDate
        self.minHour = minHour
        self.minMinute = minMinute
        self.maxHour = maxHour
        self.maxMinute = maxMinute
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title with icon
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            // Date and time controls
            HStack(spacing: 16) {
                // Date picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    DatePicker("", selection: $date, in: minDate...maxDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
                .background(Color(.systemBackground))
                
                // Time picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        // Hour picker
                        Menu {
                            ForEach(0..<24, id: \.self) { h in
                                if (minHour == nil || h > minHour! || (h == minHour! && (minMinute == nil || minute > minMinute!))) && (maxHour == nil || h < maxHour! || (h == maxHour! && (maxMinute == nil || minute <= maxMinute!))) {
                                    Button(String(format: "%02d", h)) {
                                        hour = h
                                        // If hour is set to minHour, reset minute to minMinute or 0
                                        if let minHour = minHour, h == minHour, let minMinute = minMinute, minute < minMinute {
                                            minute = minMinute
                                        }
                                        // If hour is set to maxHour, reset minute to maxMinute if needed
                                        if let maxHour = maxHour, h == maxHour, let maxMinute = maxMinute, minute > maxMinute {
                                            minute = maxMinute
                                        }
                                    }
                                }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(String(format: "%02d", hour))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("HR")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text(":")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Minute picker
                        Menu {
                            ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                                if (minHour == nil || hour > minHour! || (hour == minHour! && m > (minMinute ?? -1))) && (maxHour == nil || hour < maxHour! || (hour == maxHour! && m <= (maxMinute ?? 60))) {
                                    Button(String(format: "%02d", m)) {
                                        minute = m
                                    }
                                }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(String(format: "%02d", minute))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("MIN")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6).opacity(0.3))
        )
    }
} 