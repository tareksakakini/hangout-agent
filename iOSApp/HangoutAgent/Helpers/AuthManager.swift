import FirebaseAuth

class AuthManager {
    
    static let shared = AuthManager()
    
    private init() {}
    
    // Signs up a new user with email and password
    func signup(email: String, password: String) async throws -> FirebaseAuth.User {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Send email verification immediately after account creation
            try await sendEmailVerification()
            
            return authResult.user
        } catch {
            throw error
        }
    }
    
    // Send email verification to current user
    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        
        try await user.sendEmailVerification()
        print("📧 Email verification sent to: \(user.email ?? "unknown")")
    }
    
    // Check if current user's email is verified
    func isEmailVerified() -> Bool {
        guard let user = Auth.auth().currentUser else {
            return false
        }
        return user.isEmailVerified
    }
    
    // Reload user to get updated verification status
    func reloadUser() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        try await user.reload()
    }
    
    // Signs in an existing user with email and password
    func signin(email: String, password: String) async throws -> FirebaseAuth.User {
        do {
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            return authResult.user
        } catch {
            throw error
        }
    }
    
    func signout() throws {
        try Auth.auth().signOut()
    }
    
    func deleteUserAuth() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        
        do {
            try await user.delete()
            print("User account deleted from Firebase Auth")
        } catch {
            print("Error deleting user account: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getCurrentUser() -> FirebaseAuth.User? {
        return Auth.auth().currentUser
    }
    
    // Send password reset email
    func sendPasswordResetEmail(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            print("📧 Password reset email sent to: \(email)")
        } catch {
            print("❌ Error sending password reset email: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Change password for current user
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }
        
        guard let email = user.email else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "User email not found"])
        }
        
        do {
            // Re-authenticate user with current password
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            try await user.reauthenticate(with: credential)
            
            // Update to new password
            try await user.updatePassword(to: newPassword)
            print("✅ Password updated successfully")
        } catch {
            print("❌ Error changing password: \(error.localizedDescription)")
            throw error
        }
    }
}
