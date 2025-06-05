//
//  EventCardView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct EventCardView: View {
    let eventCard: EventCard
    @State private var showEventDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Image section
            AsyncImage(url: URL(string: eventCard.imageUrl)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(height: 120)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            
            // Content section
            VStack(alignment: .leading, spacing: 8) {
                // Activity title
                Text(eventCard.activity)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Location
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text(eventCard.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Date and time
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("\(formatDate(eventCard.date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.green)
                    Text("\(eventCard.startTime) - \(eventCard.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Description
                Text(eventCard.description)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.top, 4)
                
                // Attendees if available
                if let attendees = eventCard.attendees, !attendees.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text("Attendees:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // See Details button
                Button(action: {
                    showEventDetail = true
                }) {
                    HStack {
                        Image(systemName: "ellipsis")
                        Text("See Details")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
        .sheet(isPresented: $showEventDetail) {
            EventDetailView(eventCard: eventCard)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEEE, MMM d, yyyy"
        return displayFormatter.string(from: date)
    }
}