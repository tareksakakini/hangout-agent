//
//  HangoutAgentApp.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 4/21/25.
//

import SwiftUI
import FirebaseCore
import OneSignalFramework

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
        
        // Enable verbose logging for debugging (remove in production)
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        // Initialize with your OneSignal App ID
        OneSignal.initialize("7ff9c8ac-015f-4435-acbf-13190888af5a", withLaunchOptions: launchOptions)
        // Use this method to prompt for push notifications.
        // We recommend removing this method after testing and instead use In-App Messages to prompt for notification permission.
        OneSignal.Notifications.requestPermission({ accepted in
            print("User accepted notifications: \(accepted)")
        }, fallbackToSettings: false)
        
        return true
    }
}
