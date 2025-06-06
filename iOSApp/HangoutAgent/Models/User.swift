//
//  User.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import Foundation

struct User: Identifiable, Codable {
    var id: String = ""
    var fullname: String = ""
    var username: String = ""
    var email: String = ""
    var password: String = ""
    var subscriptions: [String] = []
    var isEmailVerified: Bool = false
    var profileImageUrl: String? = nil
    var homeCity: String? = nil
    
    func initFromFirestore(userData: [String: Any]) -> User {
        var user = User()
        user.id = userData["uid"] as? String ?? ""
        user.fullname = userData["fullname"] as? String ?? ""
        user.username = userData["username"] as? String ?? ""
        user.email = userData["email"] as? String ?? ""
        user.subscriptions = userData["subscriptions"] as? [String] ?? []
        user.isEmailVerified = userData["isEmailVerified"] as? Bool ?? false
        user.profileImageUrl = userData["profileImageUrl"] as? String
        user.homeCity = userData["homeCity"] as? String
        return user
    }
}