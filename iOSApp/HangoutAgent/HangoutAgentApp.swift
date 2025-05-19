//
//  HangoutAgentApp.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/21/25.
//

import SwiftUI
import FirebaseCore

@main
struct HangoutAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var vm = ViewModel()
    
    var body: some Scene {
        WindowGroup {
            StartingView()
                .environmentObject(vm)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    print ("Firebase configured")
    return true
  }
}
