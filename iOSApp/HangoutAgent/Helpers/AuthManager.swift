import FirebaseAuth

class AuthManager {
    
    static let shared = AuthManager()
    
    private init() {}
    
    // Signs up a new user with email and password
    func signup(email: String, password: String) async throws -> FirebaseAuth.User {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            return authResult.user
        } catch {
            throw error
        }
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
}
