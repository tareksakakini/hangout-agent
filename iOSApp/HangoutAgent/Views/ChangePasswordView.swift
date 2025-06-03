//
//  ChangePasswordView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    @State private var isCurrentPasswordVisible = false
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    private var canChangePassword: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 6
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Compact header (removed duplicate title)
                VStack(spacing: 8) {
                    Image(systemName: "key.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)
                
                // Result message (compact)
                if showResult {
                    HStack(spacing: 8) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isSuccess ? .green : .red)
                        Text(resultMessage)
                            .font(.subheadline)
                            .foregroundColor(isSuccess ? .green : .red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background((isSuccess ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Form fields (with distinct white backgrounds)
                VStack(spacing: 16) {
                    // Current password
                    HStack {
                        SwiftUI.Group {
                            if isCurrentPasswordVisible {
                                TextField("Current password", text: $currentPassword)
                            } else {
                                SecureField("Current password", text: $currentPassword)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        
                        Button(action: { isCurrentPasswordVisible.toggle() }) {
                            Image(systemName: isCurrentPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    // New password
                    VStack(spacing: 4) {
                        HStack {
                            SwiftUI.Group {
                                if isNewPasswordVisible {
                                    TextField("New password", text: $newPassword)
                                } else {
                                    SecureField("New password", text: $newPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            
                            Button(action: { isNewPasswordVisible.toggle() }) {
                                Image(systemName: isNewPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        if !newPassword.isEmpty && newPassword.count < 6 {
                            HStack {
                                Text("At least 6 characters required")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                    
                    // Confirm password
                    VStack(spacing: 4) {
                        HStack {
                            SwiftUI.Group {
                                if isConfirmPasswordVisible {
                                    TextField("Confirm new password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm new password", text: $confirmPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            
                            Button(action: { isConfirmPasswordVisible.toggle() }) {
                                Image(systemName: isConfirmPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            HStack {
                                Text("Passwords don't match")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Action button
                Button(action: {
                    Task { await changePassword() }
                }) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14))
                        }
                        Text(isLoading ? "Updating..." : "Update Password")
                    .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canChangePassword && !isLoading ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                }
                .disabled(!canChangePassword || isLoading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Spacer()
        }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func changePassword() async {
        isLoading = true
        showResult = false
        
        let result = await vm.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        
        isLoading = false
        isSuccess = result.success
        
        if result.success {
            resultMessage = "Password updated successfully!"
            
            // Clear the form
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            
            // Auto-dismiss after success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } else {
            resultMessage = result.errorMessage ?? "Update failed"
        }
        
        showResult = true
        
        // Auto-hide error message
        if !result.success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                showResult = false
            }
        }
    }
}
