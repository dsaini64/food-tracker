import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("📱 App launched")
        // Setup quick actions when app finishes launching
        setupQuickActions()
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Handle Oura OAuth callback
        if url.scheme == "foodtracker" && url.host == "oura-callback" {
            OuraManager.shared.handleCallback(url: url)
            return true
        }
        return false
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        print("📱 Configuring scene")
        let sceneConfiguration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = SceneDelegate.self
        return sceneConfiguration
    }
    
    private func setupQuickActions() {
        // Create quick action items without subtitles to avoid the grey color issue
        let scanFoodAction = UIApplicationShortcutItem(
            type: "com.foodtracker.camera",
            localizedTitle: "Scan Food",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "camera.viewfinder"),
            userInfo: nil
        )
        
        let todaySummaryAction = UIApplicationShortcutItem(
            type: "com.foodtracker.today",
            localizedTitle: "Today's Summary",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "chart.pie.fill"),
            userInfo: nil
        )
        
        let insightsAction = UIApplicationShortcutItem(
            type: "com.foodtracker.insights",
            localizedTitle: "View Insights",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "chart.line.uptrend.xyaxis"),
            userInfo: nil
        )
        
        // Set the shortcut items
        UIApplication.shared.shortcutItems = [scanFoodAction, todaySummaryAction, insightsAction]
        
        print("✅ Quick Actions registered: \(UIApplication.shared.shortcutItems?.count ?? 0) items")
    }
}

// Scene Delegate to handle quick actions properly
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        print("🚀 Quick Action triggered: \(shortcutItem.type)")
        handleQuickAction(shortcutItem)
        completionHandler(true)
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print("🔗 Scene connecting")
        // Handle quick action if app was launched from one
        if let shortcutItem = connectionOptions.shortcutItem {
            print("🚀 App launched with quick action: \(shortcutItem.type)")
            // Delay to allow SwiftUI to set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.handleQuickAction(shortcutItem)
            }
        }
    }
    
    private func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) {
        print("🎯 handleQuickAction: \(shortcutItem.type)")
        
        // Use UserDefaults synchronously - this will trigger @AppStorage in the app
        UserDefaults.standard.set(shortcutItem.type, forKey: "pendingQuickAction")
        UserDefaults.standard.synchronize()
        
        print("✅ Stored quick action in UserDefaults: \(shortcutItem.type)")
    }
}

