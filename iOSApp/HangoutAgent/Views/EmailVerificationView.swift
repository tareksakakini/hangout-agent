//
//  EmailVerificationView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct EmailVerificationView: View {
    @EnvironmentObject private var vm: ViewModel
    @State private var isCheckingVerification = false
    @State private var isResendingEmail = false
    @State private var showSuccessMessage = false
    @State private var showNotVerifiedMessage = false
    @State private var emailResent = false
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Email icon
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.bottom, 10)
                
                // Title
                Text("Verify Your Email")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                
                // Subtitle
                VStack(spacing: 8) {
                    Text("We sent a verification link to:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(vm.signedInUser?.email ?? "your email")
                        .font(.title3.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Instructions
                Text("Please check your inbox and click the verification link to continue using the app.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Success message when verification is found
                if showSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Email verified successfully!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Not verified message
                if showNotVerifiedMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Email not verified yet")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        VStack(spacing: 4) {
                            Text("Please check your inbox (including spam/junk folder)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("and click the verification link, then try again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Email resent confirmation
                if emailResent {
                    HStack {
                        Image(systemName: "paperplane.circle.fill")
                            .foregroundColor(.blue)
                        Text("Verification email sent!")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            isCheckingVerification = true
                            // Hide any previous messages
                            showNotVerifiedMessage = false
                            showSuccessMessage = false
                            
                            await vm.checkEmailVerificationStatus()
                            
                            if vm.signedInUser?.isEmailVerified == true {
                                showSuccessMessage = true
                                // Brief delay to show success message before proceeding
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    // The UI will automatically update due to the state change
                                }
                            } else {
                                // Show not verified message
                                showNotVerifiedMessage = true
                                
                                // Auto-hide the message after a few seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                    showNotVerifiedMessage = false
                                }
                            }
                            
                            isCheckingVerification = false
                        }
                    }) {
                        HStack {
                            if isCheckingVerification {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text(isCheckingVerification ? "Checking..." : "I've Verified My Email")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                    .disabled(isCheckingVerification)
                    
                    Button(action: {
                        Task {
                            isResendingEmail = true
                            // Hide previous messages
                            emailResent = false
                            showNotVerifiedMessage = false
                            
                            let success = await vm.resendVerificationEmail()
                            isResendingEmail = false
                            
                            if success {
                                emailResent = true
                                // Auto-hide the confirmation after a few seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    emailResent = false
                                }
                            }
                        }
                    }) {
                        HStack {
                            if isResendingEmail {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.orange)
                            } else {
                                Image(systemName: "envelope.arrow.triangle.branch")
                            }
                            Text(isResendingEmail ? "Sending..." : "Resend Verification Email")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                        .shadow(radius: 5)
                    }
                    .disabled(isResendingEmail)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Sign out option
                Button("Sign Out") {
                    Task {
                        await vm.signoutButtonPressed()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            // Check verification status when the view appears
            Task {
                await vm.checkEmailVerificationStatus()
            }
        }
    }
}