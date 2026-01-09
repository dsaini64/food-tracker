//
//  AppGroupConstants.swift
//  FoodTracker
//
//  Shared constants for App Group configuration
//

import Foundation

/// Shared constants for App Group communication between the main app and widgets
enum AppGroupConstants {
    /// The App Group identifier used to share data between the app and its extensions
    /// 
    /// ⚠️ IMPORTANT: This must be configured in Xcode:
    /// 1. Select your main app target → Signing & Capabilities → + Capability → App Groups
    /// 2. Add this exact identifier: "group.com.divakar.foodsnap.app"
    /// 3. Repeat for your widget extension target
    /// 
    /// Note: If you get errors, make sure this matches your app's bundle identifier pattern.
    /// For example, if your bundle ID is "com.yourname.foodtracker", use "group.com.yourname.foodtracker"
    static let appGroupIdentifier = "group.com.divakar.foodsnap.app"
    
    /// Shared UserDefaults instance for App Group communication
    /// Returns nil if App Group is not properly configured
    static var shared: UserDefaults? {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        
        #if DEBUG
        if defaults == nil {
            print("⚠️⚠️⚠️ CRITICAL: App Group '\(appGroupIdentifier)' not available!")
            print("⚠️⚠️⚠️ Configure App Groups in Xcode: Signing & Capabilities > App Groups")
            print("⚠️⚠️⚠️ Add '\(appGroupIdentifier)' to both app and widget targets")
        }
        #endif
        
        return defaults
    }
    
    // MARK: - UserDefaults Keys
    enum Keys {
        static let todayCalories = "widget_todayCalories"
        static let todayProtein = "widget_todayProtein"
        static let todayCarbs = "widget_todayCarbs"
        static let todayFat = "widget_todayFat"
        static let todayFoodCount = "widget_todayFoodCount"
        static let lastUpdateDate = "widget_lastUpdateDate"
    }
}
