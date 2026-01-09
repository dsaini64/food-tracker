import SwiftUI
import UIKit

@main
struct foodtrackerv2App: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("pendingQuickAction") private var pendingQuickAction: String = ""
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("🚀🚀🚀 APP STARTING - hasCompletedOnboarding: \(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))")
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView(pendingQuickAction: $pendingQuickAction)
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                        // Handle deep links
                        if let url = userActivity.webpageURL {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("DeepLink"),
                                object: nil,
                                userInfo: ["url": url]
                            )
                        }
                    }
                    .onOpenURL { url in
                        // Handle Oura OAuth callback
                        if url.scheme == "foodtracker" && url.host == "oura-callback" {
                            OuraManager.shared.handleCallback(url: url)
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .onAppear {
                        // Clear any pending quick action during onboarding
                        if !pendingQuickAction.isEmpty {
                            print("⚠️ Quick action ignored - onboarding not complete")
                            pendingQuickAction = ""
                        }
                    }
            }
        }
    }
}
