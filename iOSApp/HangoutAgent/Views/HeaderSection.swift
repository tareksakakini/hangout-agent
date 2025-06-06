import SwiftUI

struct HeaderSection: View {
    init() {}
    
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 35, weight: .medium))
                        .foregroundColor(.white)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 15, x: 0, y: 8)
            VStack(spacing: 8) {
                Text("Create AI Agent")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Build your personalized hangout coordinator")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }
} 