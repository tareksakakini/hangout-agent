import SwiftUI

struct ErrorMessageSection: View {
    let errorMessage: String?
    
    init(errorMessage: String?) {
        self.errorMessage = errorMessage
    }
    
    var body: some View {
        if let errorMessage = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            .transition(.scale.combined(with: .opacity))
        }
    }
} 