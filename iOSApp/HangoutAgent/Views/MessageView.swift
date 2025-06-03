//
//  MessageView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI

struct MessageView: View {
    @State var text: String
    @State var alignment: Alignment
    @State var timestamp: Date
    
    var body: some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 4) {
            Text(text)
                .padding()
                .background(alignment == .leading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            
            Text(formatTimestamp(timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: UIScreen.main.bounds.width / 2, alignment: alignment)
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

