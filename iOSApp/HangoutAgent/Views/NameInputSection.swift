import SwiftUI

struct NameInputSection: View {
    @Binding var name: String
    
    init(name: Binding<String>) {
        self._name = name
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                Text("Agent Name")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            TextField("Enter agent name...", text: $name)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(name.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
    }
} 