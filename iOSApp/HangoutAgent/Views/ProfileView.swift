//
//  ProfileView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var vm: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    var user: User? = nil
    
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteResult: (success: Bool, message: String)? = nil
    @State private var showDeleteResult = false
    @State private var showChangePassword = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var isUploadingImage = false
    @State private var uploadResult: (success: Bool, message: String)? = nil
    @State private var showUploadResult = false
    @State private var imageRefreshId = UUID()
    @State private var isRemovingImage = false
    @State private var showPhotoActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var showImageCrop = false
    @State private var isEditingHomeCity = false
    @State private var editedHomeCity = ""
    @State private var isUpdatingHomeCity = false
    @State private var homeCityUpdateResult: (success: Bool, message: String)? = nil
    @State private var showHomeCityUpdateResult = false
    @State private var showFullSizeImage = false

    var isCurrentUser: Bool {
        guard let user = user else { return true }
        return user.id == vm.signedInUser?.id
    }
    
    var displayUser: User? {
        user ?? vm.signedInUser
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // User Info Section
                if let user = displayUser {
                    VStack(spacing: 20) {
                        // Profile Avatar
                        VStack(spacing: 12) {
                            ZStack {
                                if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                                        switch phase {
                                        case .empty:
                                            Circle()
                                                .fill(Color.black.opacity(0.1))
                                                .frame(width: 90, height: 90)
                                                .overlay(
                                                    ProgressView()
                                                        .tint(.black.opacity(0.6))
                                                )
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 90, height: 90)
                                                .clipShape(Circle())
                                                .onTapGesture {
                                                    if !isCurrentUser { showFullSizeImage = true }
                                                }
                                        case .failure(_):
                                            Circle()
                                                .fill(Color.black)
                                                .frame(width: 90, height: 90)
                                                .overlay(
                                                    Text(user.fullname.prefix(1))
                                                        .font(.system(size: 32, weight: .medium, design: .rounded))
                                                        .foregroundColor(.white)
                                                )
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                    .id(imageRefreshId)
                                } else {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 90, height: 90)
                                        .overlay(
                                            Text(user.fullname.prefix(1))
                                                .font(.system(size: 32, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)
                                        )
                                }
                                // Only show edit button for current user
                                if isCurrentUser {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Button(action: {
                                                showPhotoActionSheet = true
                                            }) {
                                                Image(systemName: "camera.fill")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.black.opacity(0.7))
                                            }
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                        .offset(x: 30, y: 30)
                                }
                            }
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        }
                        .padding(.top, 32)
                        // User Info Card
                        VStack(spacing: 24) {
                            Text(user.fullname)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            VStack(spacing: 20) {
                                // Username row
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Username")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        Text(user.username)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                }
                                Rectangle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(height: 1)
                                // Home City row
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "location.circle")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.black.opacity(0.7))
                                        )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Home City")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        Text(user.homeCity?.isEmpty == false ? user.homeCity! : "Not set")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(user.homeCity?.isEmpty == false ? .primary : .black.opacity(0.4))
                                    }
                                    Spacer()
                                }
                            }
                            .padding(28)
                            .background(Color.white)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    // Only show editing and account actions for current user
                    if isCurrentUser {
                        // Home city update result message
                        if showHomeCityUpdateResult, let result = homeCityUpdateResult {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(result.success ? .black.opacity(0.7) : .black.opacity(0.7))
                                Text(result.message)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .transition(.scale.combined(with: .opacity))
                        }
                        // Account deletion result message
                        if showDeleteResult, let result = deleteResult {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(result.success ? .black.opacity(0.7) : .black.opacity(0.7))
                                Text(result.message)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .transition(.scale.combined(with: .opacity))
                        }
                        // Action Buttons Section - Clean design
                        VStack(spacing: 16) {
                            // Change Password Button
                            Button(action: {
                                showChangePassword = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "key")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.black.opacity(0.7))
                                    Text("Change Password")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.black.opacity(0.3))
                                }
                                .padding(20)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                            }
                            // Sign Out Button
                            Button(action: {
                                Task {
                                    await vm.signoutButtonPressed()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.right.square")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.black.opacity(0.7))
                                    Text("Sign Out")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.black.opacity(0.3))
                                }
                                .padding(20)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                            }
                            // Delete Account Button
                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                HStack(spacing: 12) {
                                    if isDeletingAccount {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.black.opacity(0.7))
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.black.opacity(0.7))
                                    }
                                    Text(isDeletingAccount ? "Deleting Account..." : "Delete Account")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if !isDeletingAccount {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.black.opacity(0.3))
                                    }
                                }
                                .padding(20)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isDeletingAccount)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .background(Color(.systemGray6))
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
            }
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordView()
                .environmentObject(vm)
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                isDeletingAccount = true
                Task {
                    let result = await vm.deleteAccountButtonPressed()
                    
                    DispatchQueue.main.async {
                        isDeletingAccount = false
                        deleteResult = (success: result.success, message: result.errorMessage ?? "Account deleted successfully")
                        showDeleteResult = true
                        
                        // Auto-hide the message after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            showDeleteResult = false
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone. Your account and all associated data will be permanently deleted.")
        }
        .confirmationDialog(
            "Profile Picture",
            isPresented: $showPhotoActionSheet,
            titleVisibility: .visible
        ) {
            if let user = displayUser, let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                // User has a profile picture - show change and remove options
                Button("Change Photo") {
                    showPhotoPicker = true
                }
                
                Button("Remove Photo", role: .destructive) {
                    Task {
                        await removeProfileImage()
                    }
                }
                
                Button("Cancel", role: .cancel) { }
            } else {
                // User has no profile picture - show add option
                Button("Add Photo") {
                    showPhotoPicker = true
                }
                
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            if let user = displayUser, let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                Text("Choose an option for your profile picture")
            } else {
                Text("Add a profile picture to personalize your account")
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: $showImageCrop) {
            if let image = selectedImage {
                ImageCropView(
                    image: image,
                    onCrop: { croppedImage in
                        Task {
                            await uploadProfileImage(croppedImage)
                        }
                        showImageCrop = false
                        selectedImage = nil
                    },
                    onCancel: {
                        showImageCrop = false
                        selectedImage = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showFullSizeImage) {
            if let profileImageUrl = displayUser?.profileImageUrl, !profileImageUrl.isEmpty {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    AsyncImage(url: URL(string: profileImageUrl)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.gray)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemBackground))
                        case .failure(_):
                            Image(systemName: "person.crop.circle.badge.exclam")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .foregroundColor(.gray.opacity(0.7))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showFullSizeImage = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray.opacity(0.8))
                                    .padding()
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .onChange(of: displayUser?.profileImageUrl) { oldValue, newValue in
            // Force image refresh when profile URL changes
            if oldValue != newValue && newValue != nil {
                imageRefreshId = UUID()
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue {
                    // Convert PhotosPickerItem to UIImage for cropping
                    do {
                        guard let imageData = try await photoItem.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: imageData) else {
                            uploadResult = (false, "Failed to process image")
                            showUploadResult = true
                            selectedPhotoItem = nil
                            return
                        }
                        
                        DispatchQueue.main.async {
                            self.selectedImage = uiImage
                            self.showImageCrop = true
                            self.selectedPhotoItem = nil // Clear the picker selection
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.uploadResult = (false, "Failed to load image")
                            self.showUploadResult = true
                            self.selectedPhotoItem = nil
                        }
                    }
                }
            }
        }
    }
    
    private func uploadProfileImage(_ uiImage: UIImage) async {
        isUploadingImage = true
        showUploadResult = false
        
        // Upload the image
        let result = await vm.uploadProfileImage(uiImage)
        
        DispatchQueue.main.async {
            self.isUploadingImage = false
            self.uploadResult = (result.success, result.success ? "Profile picture updated!" : result.errorMessage ?? "Upload failed")
            self.showUploadResult = true
            
            // Force image refresh on successful upload
            if result.success {
                self.imageRefreshId = UUID()
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showUploadResult = false
            }
        }
    }
    
    private func removeProfileImage() async {
        isRemovingImage = true
        showUploadResult = false
        
        let result = await vm.removeProfileImage()
        
        DispatchQueue.main.async {
            self.isRemovingImage = false
            self.uploadResult = (result.success, result.success ? "Profile picture removed!" : result.errorMessage ?? "Failed to remove profile picture")
            self.showUploadResult = true
            
            // Force image refresh on successful removal
            if result.success {
                self.imageRefreshId = UUID()
                // Clear the selected photo item to ensure PhotosPicker works for next selection
                self.selectedPhotoItem = nil
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showUploadResult = false
            }
        }
    }
    
    private func updateHomeCity() async {
        isUpdatingHomeCity = true
        showHomeCityUpdateResult = false
        
        let result = await vm.updateHomeCity(city: editedHomeCity.trimmingCharacters(in: .whitespacesAndNewlines))
        
        DispatchQueue.main.async {
            self.isUpdatingHomeCity = false
            self.homeCityUpdateResult = (result.success, result.success ? "Home city updated successfully!" : result.errorMessage ?? "Failed to update home city")
            self.showHomeCityUpdateResult = true
            
            if result.success {
                self.isEditingHomeCity = false
            }
            
            // Auto-hide the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showHomeCityUpdateResult = false
            }
        }
    }
}