import SwiftUI

struct DateRangeSection: View {
    @Binding var planningStartDate: Date
    @Binding var planningEndDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Planning Date Range")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("Set the date range for which the agent will coordinate plans")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(nil)
            
            // Date range pickers
            VStack(spacing: 16) {
                // Start date
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                            .frame(width: 16)
                        
                        Text("Start Date")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    DatePicker("Start Date", selection: $planningStartDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                
                // End date  
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 16)
                        
                        Text("End Date")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    DatePicker("End Date", selection: $planningEndDate, in: planningStartDate..., displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
            }
            .background(Color(.systemBackground))
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
