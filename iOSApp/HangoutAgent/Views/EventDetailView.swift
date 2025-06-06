//
//  EventDetailView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct EventDetailView: View {
    let eventCard: EventCard
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: ViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Image Section
                    AsyncImage(url: URL(string: eventCard.imageUrl)) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 250)
                                .overlay(
                                    ProgressView()
                                        .tint(.gray)
                                )
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 250)
                                .clipped()
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 250)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        Text("Image not available")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    // Event Information
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        Text(eventCard.activity)
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // Date & Time Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "calendar")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text(formatDate(eventCard.date))
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "clock")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.green)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Time")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text("\(eventCard.startTime) - \(eventCard.endTime)")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Location Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.red)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text(eventCard.location)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Description Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About this event")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text(eventCard.description)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        
                        // Attendees Section (if available)
                        if let attendees = eventCard.attendees, !attendees.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Who's coming")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(attendees, id: \.self) { attendee in
                                        AttendeeRowView(attendeeName: attendee)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.5))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGray6))
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        return displayFormatter.string(from: date)
    }
}