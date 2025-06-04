//
//  ForgotPasswordView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Icon
                    Image(systemName: "key.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.bottom, 10)
                    
                    // Title
                    Text("Reset Password")
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                    
                    // Instructions
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    // Result message
                    if showResult {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isSuccess ? .green : .red)
                                Text(isSuccess ? "Reset Email Sent!" : "Reset Failed")
                                    .font(.headline)
                                    .foregroundColor(isSuccess ? .green : .red)
                            }
                            
                            Text(resultMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .background((isSuccess ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Email input and button
                    VStack(spacing: 16) {
                        TextField("Email Address", text: $email)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        Button(action: {
                            Task {
                                await sendPasswordReset()
                            }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isLoading ? "Sending..." : "Send Reset Email")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(email.isEmpty || isLoading ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                        }
                        .disabled(email.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Reset Password")
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
    
    private func sendPasswordReset() async {
        isLoading = true
        showResult = false
        
        let result = await vm.sendPasswordResetEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        
        isLoading = false
        isSuccess = result.success
        
        if result.success {
            resultMessage = "Check your inbox for password reset instructions. Don't forget to check your spam folder!"
        } else {
            resultMessage = result.errorMessage ?? "Failed to send reset email"
        }
        
        showResult = true
        
        // Auto-hide result message after some time
        DispatchQueue.main.asyncAfter(deadline: .now() + (result.success ? 5.0 : 8.0)) {
            showResult = false
            
            // If successful, auto-dismiss the sheet after showing success message
            if result.success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        }
    }
}