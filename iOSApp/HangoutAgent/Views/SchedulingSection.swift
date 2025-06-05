import SwiftUI

struct SchedulingSection: View {
    @Binding var availabilityDate: Date
    @Binding var availabilityHour: Int
    @Binding var availabilityMinute: Int
    @Binding var suggestionsDate: Date
    @Binding var suggestionsHour: Int
    @Binding var suggestionsMinute: Int
    @Binding var finalPlanDate: Date
    @Binding var finalPlanHour: Int
    @Binding var finalPlanMinute: Int
    var timeZone: String
    
    init(
        availabilityDate: Binding<Date>,
        availabilityHour: Binding<Int>,
        availabilityMinute: Binding<Int>,
        suggestionsDate: Binding<Date>,
        suggestionsHour: Binding<Int>,
        suggestionsMinute: Binding<Int>,
        finalPlanDate: Binding<Date>,
        finalPlanHour: Binding<Int>,
        finalPlanMinute: Binding<Int>,
        timeZone: String
    ) {
        self._availabilityDate = availabilityDate
        self._availabilityHour = availabilityHour
        self._availabilityMinute = availabilityMinute
        self._suggestionsDate = suggestionsDate
        self._suggestionsHour = suggestionsHour
        self._suggestionsMinute = suggestionsMinute
        self._finalPlanDate = finalPlanDate
        self._finalPlanHour = finalPlanHour
        self._finalPlanMinute = finalPlanMinute
        self.timeZone = timeZone
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Agent Schedule")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Text("Configure specific dates and times when your agent should send different types of messages")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            VStack(spacing: 16) {
                SchedulingPickerRow(title: "Ask for Availability", date: $availabilityDate, hour: $availabilityHour, minute: $availabilityMinute)
                SchedulingPickerRow(title: "Send Suggestions", date: $suggestionsDate, hour: $suggestionsHour, minute: $suggestionsMinute)
                SchedulingPickerRow(title: "Send Final Plan", date: $finalPlanDate, hour: $finalPlanHour, minute: $finalPlanMinute)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(16)
    }
}

struct SchedulingPickerRow: View {
    let title: String
    @Binding var date: Date
    @Binding var hour: Int
    @Binding var minute: Int
    
    init(title: String, date: Binding<Date>, hour: Binding<Int>, minute: Binding<Int>) {
        self.title = title
        self._date = date
        self._hour = hour
        self._minute = minute
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            HStack(spacing: 12) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .frame(maxWidth: .infinity)
                
                HStack(spacing: 4) {
                    Picker("Hour", selection: $hour) {
                        ForEach(0..<24) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 65)
                    Text(":")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Picker("Minute", selection: $minute) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 65)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
} 