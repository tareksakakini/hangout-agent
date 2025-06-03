//
//  StartingView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI

struct StartingView: View {
    @EnvironmentObject private var vm: ViewModel
    @State var loginPressed: Bool = false
    @State var signupPressed: Bool = false
    
    var body: some View {
        NavigationStack {
            if let user = vm.signedInUser {
                // User is signed in -> check verification status
                if user.isEmailVerified {
                    // Verified user -> go to HomeView
                HomeView()
                } else {
                    // Unverified user -> go to EmailVerificationView
                    EmailVerificationView()
                }
            } else {
                // Not signed in -> show login/signup options
                ZStack {
                    Color(.systemGray6)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 40) {
                        Image("yalla_agent_transparent")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(.top, 60)
                        
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Button(action: {
                                loginPressed = true
                            }) {
                                Text("Log In")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            }
                            .padding(.horizontal, 40)
                            .navigationDestination(isPresented: $loginPressed) {
                                LoginView()
                            }
                            
                            Button(action: {
                                signupPressed = true
                            }) {
                                Text("Sign Up")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.blue)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                                    .shadow(radius: 4)
                            }
                            .padding(.horizontal, 40)
                            .navigationDestination(isPresented: $signupPressed) {
                                SignupView()
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}
