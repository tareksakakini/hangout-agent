//
//  SignupView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct SignupView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State var fullname: String = ""
    @State var username: String = ""
    @State var email: String = ""
    @State var password: String = ""
    @State var homeCity: String = ""
    @State var goToNextScreen: Bool = false
    @State var isPasswordVisible = false
    @State var user: User? = nil
    @State var showSuccessMessage = false
    @State private var isCheckingUsername = false
    @State private var isUsernameTaken: Bool? = nil
    @FocusState private var usernameFieldIsFocused: Bool
    
    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Logo
                Image("yalla_agent_transparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding(.top, 40)
                
                // Title
                Text("Create Account")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                    .padding(.bottom, 20)
                
                SignupSheet
                
                // Success message
                if showSuccessMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Account created successfully!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        Text("Please check your email to verify your account")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

extension SignupView {
    private var SignupSheet: some View {
        VStack(spacing: 16) {
            UserFields
            SignUpButton
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }
    
    private var UserFields: some View {
        VStack(spacing: 16) {
            FullnameField
            UsernameField
            EmailField
            HomeCityField
            PasswordField
        }
    }
    
    private var FullnameField: some View {
        TextField("Full Name", text: $fullname)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
    }
    
    private var UsernameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .trailing) {
                TextField("Username", text: $username)
                    .padding(.trailing, 36) // Add right padding for icon
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(10)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($usernameFieldIsFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                usernameFieldIsFocused ? (isUsernameTaken == true ? Color.red : (isUsernameTaken == false && !username.isEmpty ? Color.green : Color.clear)) : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .onChange(of: username) { newValue in
                        isUsernameTaken = nil
                        if newValue.isEmpty { return }
                        isCheckingUsername = true
                        // Debounce: wait 0.5s after last change
                        let currentUsername = newValue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if username == currentUsername {
                                Task {
                                    let taken = await vm.isUsernameTaken(currentUsername)
                                    DispatchQueue.main.async {
                                        isUsernameTaken = taken
                                        isCheckingUsername = false
                                    }
                                }
                            }
                        }
                    }
                if usernameFieldIsFocused {
                    if isCheckingUsername {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 12)
                    } else if isUsernameTaken == true {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .padding(.trailing, 12)
                    } else if isUsernameTaken == false && !username.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .padding(.trailing, 12)
                    }
                }
            }
            if usernameFieldIsFocused {
                if isUsernameTaken == true {
                    Text("Username is already taken")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if isUsernameTaken == false && !username.isEmpty {
                    Text("Username is available")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private var EmailField: some View {
        TextField("Email", text: $email)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
    }
    
    private var HomeCityField: some View {
        TextField("Home City", text: $homeCity)
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
    }
    
    private var PasswordField: some View {
        HStack {
            SwiftUI.Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            
            Button(action: {
                isPasswordVisible.toggle()
            }) {
                Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(.gray)
            }
            .padding(.leading, 8)
        }
    }
    
    private var SignUpButton: some View {
        Button {
            Task {
                if isUsernameTaken == true {
                    return // Prevent sign up if taken
                }
                if let signedUpUser = await vm.signupButtonPressed(fullname: fullname, username: username, email: email, password: password, homeCity: homeCity) {
                    DispatchQueue.main.async {
                        vm.signedInUser = signedUpUser
                        showSuccessMessage = true
                        // Auto-dismiss after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            dismiss()
                        }
                    }
                }
            }
        } label: {
            Text("Sign Up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background((isUsernameTaken == true || isCheckingUsername) ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 5)
        }
        .padding(.top, 8)
        .disabled(isUsernameTaken == true || isCheckingUsername)
    }
}
