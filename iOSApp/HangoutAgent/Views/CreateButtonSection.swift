import SwiftUI

struct CreateButtonSection: View {
    let name: String
    let action: () -> Void
    
    init(name: String, action: @escaping () -> Void) {
        self.name = name
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if name.isEmpty {
                    Image(systemName: "textformat")
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                }
                Text("Create AI Agent")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: name.isEmpty ? 
                        [Color.gray.opacity(0.6), Color.gray.opacity(0.4)] :
                        [Color.blue, Color.blue.opacity(0.8)]
                    ),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: name.isEmpty ? Color.clear : Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(name.isEmpty ? 1.0 : 1.02)
            .animation(.easeInOut(duration: 0.2), value: name.isEmpty)
        }
        .disabled(name.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
} 