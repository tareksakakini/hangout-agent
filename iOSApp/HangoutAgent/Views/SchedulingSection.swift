import SwiftUI

struct SchedulingSection: View {
    @Binding var suggestionsDate: Date
    @Binding var suggestionsHour: Int
    @Binding var suggestionsMinute: Int
    @Binding var finalPlanDate: Date
    @Binding var finalPlanHour: Int
    @Binding var finalPlanMinute: Int
    var timeZone: String
    
    init(
        suggestionsDate: Binding<Date>,
        suggestionsHour: Binding<Int>,
        suggestionsMinute: Binding<Int>,
        finalPlanDate: Binding<Date>,
        finalPlanHour: Binding<Int>,
        finalPlanMinute: Binding<Int>,
        timeZone: String
    ) {
        self._suggestionsDate = suggestionsDate
        self._suggestionsHour = suggestionsHour
        self._suggestionsMinute = suggestionsMinute
        self._finalPlanDate = finalPlanDate
        self._finalPlanHour = finalPlanHour
        self._finalPlanMinute = finalPlanMinute
        self.timeZone = timeZone
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
                    minute: $suggestionsMinute
                )
                
                SchedulingPickerRow(
                    title: "Send Final Plan",
                    icon: "checkmark.seal.fill",
                    iconColor: .blue,
                    date: $finalPlanDate,
                    hour: $finalPlanHour,
                    minute: $finalPlanMinute
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
    }
}

struct SchedulingPickerRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var date: Date
    @Binding var hour: Int
    @Binding var minute: Int
    
    init(title: String, icon: String, iconColor: Color, date: Binding<Date>, hour: Binding<Int>, minute: Binding<Int>) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._date = date
        self._hour = hour
        self._minute = minute
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
                    
                    DatePicker("", selection: $date, displayedComponents: .date)
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
                                Button(String(format: "%02d", h)) {
                                    hour = h
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
                                Button(String(format: "%02d", m)) {
                                    minute = m
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