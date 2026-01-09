//
//  ContentView.swift
//  FoodTrackerApp
//
//  Created by Divakar Saini on 10/11/25.
//

import SwiftUI
import Combine
import WidgetKit
internal import AVFoundation

struct ContentView: View {
    @StateObject private var dailyLog = DailyFoodLog()
    @StateObject private var userProfile = UserProfile()
    @StateObject private var cameraPermissions = CameraPermissionManager()
    @StateObject private var foodRecognition = FoodRecognitionService()
    @StateObject private var notificationManager = NotificationManager()
    
    @State private var capturedImage: UIImage?
    @State private var selectedTab: Int
    @Binding var pendingQuickAction: String
    
    // Custom initializer to set initial tab based on pending quick action
    init(pendingQuickAction: Binding<String>) {
        self._pendingQuickAction = pendingQuickAction
        
        // Determine initial tab based on pending quick action
        let initialTab: Int
        switch pendingQuickAction.wrappedValue {
        case "com.foodtracker.camera":
            initialTab = 0
        case "com.foodtracker.today":
            initialTab = 1
        case "com.foodtracker.insights":
            initialTab = 2
        default:
            initialTab = 0 // Default to camera
        }
        
        self._selectedTab = State(initialValue: initialTab)
        
        // Clear the pending action if it was used
        if !pendingQuickAction.wrappedValue.isEmpty {
            print("📱 Initialized with quick action: \(pendingQuickAction.wrappedValue), setting initial tab to \(initialTab)")
        }
        
        // Immediately sync any existing data on initialization
        NSLog("🔵🔵🔵 ContentView INIT - About to sync existing data")
        DispatchQueue.main.async {
            Self.syncDataImmediately()
        }
    }
    
    // Static method to sync data immediately without needing instance properties
    static func syncDataImmediately() {
        // Try App Group first, also sync to standard UserDefaults as fallback
        let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        // Try to load existing data from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "SavedFoodItems"),
           let items = try? JSONDecoder().decode([FoodItem].self, from: data) {
            
            let todayItems = items.filter { item in
                Calendar.current.isDateInToday(item.timestamp)
            }
            
            let calories = todayItems.reduce(0.0) { $0 + $1.calories }
            let protein = todayItems.reduce(0.0) { $0 + $1.protein }
            let carbs = todayItems.reduce(0.0) { $0 + $1.carbs }
            let fat = todayItems.reduce(0.0) { $0 + $1.fat }
            
            // Sync to App Group if available
            if let appGroup = appGroupDefaults {
                appGroup.set(calories, forKey: "widget_todayCalories")
                appGroup.set(protein, forKey: "widget_todayProtein")
                appGroup.set(carbs, forKey: "widget_todayCarbs")
                appGroup.set(fat, forKey: "widget_todayFat")
                appGroup.set(todayItems.count, forKey: "widget_foodCount")
                appGroup.synchronize()
            }
            
            // Always sync to standard UserDefaults as fallback
            standardDefaults.set(calories, forKey: "widget_todayCalories")
            standardDefaults.set(protein, forKey: "widget_todayProtein")
            standardDefaults.set(carbs, forKey: "widget_todayCarbs")
            standardDefaults.set(fat, forKey: "widget_todayFat")
            standardDefaults.set(todayItems.count, forKey: "widget_foodCount")
            standardDefaults.synchronize()
            
            let source = appGroupDefaults != nil ? "App Group + Standard" : "Standard only"
            NSLog("🔵🔵🔵 IMMEDIATE SYNC to \(source): \(calories) cal, \(protein)g protein, \(todayItems.count) items")
            
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            NSLog("🔵🔵🔵 Widget reload requested")
            #endif
        } else {
            NSLog("🔵🔵🔵 No existing food data found to sync")
        }
    }
    
    // Computed property to create analysis with personalized goals
    private var analysis: NutritionAnalysis {
        NutritionAnalysis(dailyLog: dailyLog, goals: userProfile.nutritionGoals)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Camera Tab
            swipeableTabContent(index: 0)
            .tag(0)
            .tabItem {
                Image(systemName: "camera.fill")
                Text("Camera")
            }
            
            // Daily Summary Tab
            swipeableTabContent(index: 1)
                .tag(1)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Today")
                }
            
            // Health Insights Tab
            swipeableTabContent(index: 2)
                .tag(2)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Insights")
                }
            
            // Settings Tab
            swipeableTabContent(index: 3)
            .tag(3)
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Track the start location to determine if swipe started in a blocked area
                    // We'll check this in onEnded
                }
                .onEnded { value in
                    let horizontalMovement = abs(value.translation.width)
                    let verticalMovement = abs(value.translation.height)
                    let screenWidth = UIScreen.main.bounds.width
                    let screenHeight = UIScreen.main.bounds.height
                    let threshold = screenWidth * 0.25
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    
                    // Calculate where the swipe started (using startLocation from translation)
                    // Note: DragGesture doesn't provide startLocation directly, so we approximate
                    // by checking if the swipe is in the top or bottom areas
                    let startY = value.startLocation.y
                    let topBarHeight: CGFloat = 100 // Approximate top bar height
                    let bottomBarHeight: CGFloat = 150 // Approximate bottom area height (food items + button)
                    let isInTopBar = startY < topBarHeight
                    let isInBottomBar = startY > (screenHeight - bottomBarHeight)
                    
                    // Don't switch tabs if swipe started in top bar (calories) or bottom bar (food items)
                    if isInTopBar || isInBottomBar {
                        return
                    }
                    
                    // Only respond to clearly horizontal swipes
                    if horizontalMovement > verticalMovement * 1.5 {
                        if (value.translation.width > threshold || velocity > 300) && selectedTab > 0 {
                            // Swipe right - go to previous tab
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab -= 1
                            }
                        } else if (value.translation.width < -threshold || velocity < -300) && selectedTab < 3 {
                            // Swipe left - go to next tab
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab += 1
                            }
                        }
                    }
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FoodAnalyzed"))) { notification in
            if let foodItem = notification.object as? FoodItem {
                dailyLog.addFoodItem(foodItem)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveFoodItem"))) { notification in
            if let itemId = notification.object as? UUID {
                // Find and remove the item with this ID
                if let itemToRemove = dailyLog.foodItems.first(where: { $0.id == itemId }) {
                    dailyLog.removeFoodItem(itemToRemove)
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // Check for new day every minute
            dailyLog.checkForNewDay()
        }
        .onAppear {
            print("🎬 ContentView appeared")
            print("📊 Current food items: \(dailyLog.todayFoodItems.count) today, \(dailyLog.foodItems.count) total")
            print("📊 Today's totals: \(dailyLog.totalCalories) cal, \(dailyLog.totalProtein)g protein")
            
            // Request notification permission on app launch
            if userProfile.notificationsEnabled {
                notificationManager.requestNotificationPermission()
                // Schedule with user's custom times
                notificationManager.scheduleMealReminders(
                    breakfastTime: userProfile.breakfastTime,
                    lunchTime: userProfile.lunchTime,
                    dinnerTime: userProfile.dinnerTime
                )
            }
            
            // Force sync widget data on appear (in case it wasn't triggered during init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔄 Force syncing widget data from onAppear...")
                syncWidgetDataManually()
            }
            
            // Sync goals to widget
            syncGoalsToWidget()
            
            // Clear pending quick action (it was already handled in init)
            if !pendingQuickAction.isEmpty {
                print("📱 Clearing pending quick action that was handled in init: \(pendingQuickAction)")
                pendingQuickAction = ""
            }
        }
        .onChange(of: userProfile.age) { syncGoalsToWidget() }
        .onChange(of: userProfile.gender) { syncGoalsToWidget() }
        .onChange(of: userProfile.height) { syncGoalsToWidget() }
        .onChange(of: userProfile.weight) { syncGoalsToWidget() }
        .onChange(of: userProfile.activityLevel) { syncGoalsToWidget() }
        .onChange(of: userProfile.customCalorieGoal) { syncGoalsToWidget() }
        .onChange(of: userProfile.hasCustomCalorieGoal) { syncGoalsToWidget() }
        .onChange(of: pendingQuickAction) { oldValue, newValue in
            print("📲 pendingQuickAction changed from '\(oldValue)' to '\(newValue)'")
            if !newValue.isEmpty {
                print("📲 Handling quick action change: \(newValue)")
                handleQuickAction(newValue)
                // Clear it after handling
                pendingQuickAction = ""
            }
        }
        .onOpenURL { url in
            // Handle URL scheme deep links
            handleDeepLink(url)
        }
    }
    
    @ViewBuilder
    private func swipeableTabContent(index: Int) -> some View {
        tabView(at: index)
    }
    
    @ViewBuilder
    private func tabView(at index: Int) -> some View {
        switch index {
        case 0:
            SnapchatCameraView(
                analysis: analysis,
                foodRecognition: foodRecognition
            )
        case 1:
            DailySummaryView(analysis: analysis)
        case 2:
            HealthInsightsView(analysis: analysis)
        case 3:
            SettingsView(
                userProfile: userProfile,
                notificationManager: notificationManager
            )
        default:
            Color.clear
        }
    }
    
    private func handleQuickAction(_ actionType: String) {
        print("🎯 Handling Quick Action: \(actionType)")
        print("🎯 Current selectedTab: \(selectedTab)")
        
        // Switch tabs immediately - we're already on main thread in SwiftUI
        switch actionType {
        case "com.foodtracker.camera":
            print("📷 Setting tab to camera (0)")
            selectedTab = 0
        case "com.foodtracker.today":
            print("📊 Setting tab to today (1)")
            selectedTab = 1
        case "com.foodtracker.insights":
            print("📈 Setting tab to insights (2)")
            selectedTab = 2
        default:
            print("⚠️ Unknown action type: \(actionType)")
        }
        print("✅ selectedTab is now: \(selectedTab)")
    }
    
    private func handleDeepLink(_ url: URL) {
        // Handle URL scheme: foodtracker://camera, foodtracker://today, etc.
        switch url.host {
        case "camera":
            selectedTab = 0
        case "today":
            selectedTab = 1
        case "insights":
            selectedTab = 2
        case "settings":
            selectedTab = 3
        default:
            break
        }
    }
    
    private func syncGoalsToWidget() {
        let goals = userProfile.nutritionGoals
        // Try App Group first, also sync to standard UserDefaults as fallback
        let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        // Sync to App Group if available
        if let appGroup = appGroupDefaults {
            appGroup.set(goals.dailyCalories, forKey: "widget_goalCalories")
            appGroup.set(goals.dailyProtein, forKey: "widget_goalProtein")
            appGroup.set(goals.dailyCarbs, forKey: "widget_goalCarbs")
            appGroup.set(goals.dailyFat, forKey: "widget_goalFat")
            
            // Also sync consumed data at the same time to ensure widget has complete data
            appGroup.set(dailyLog.totalCalories, forKey: "widget_todayCalories")
            appGroup.set(dailyLog.totalProtein, forKey: "widget_todayProtein")
            appGroup.set(dailyLog.totalCarbs, forKey: "widget_todayCarbs")
            appGroup.set(dailyLog.totalFat, forKey: "widget_todayFat")
            appGroup.set(dailyLog.todayFoodItems.count, forKey: "widget_foodCount")
            
            let syncResult = appGroup.synchronize()
            if !syncResult {
                print("⚠️⚠️⚠️ WARNING: App Group synchronize() returned false!")
            }
            
            // Verify goals were written correctly
            let verifyCalGoal = appGroup.double(forKey: "widget_goalCalories")
            let verifyProtGoal = appGroup.double(forKey: "widget_goalProtein")
            let verifyCarbsGoal = appGroup.double(forKey: "widget_goalCarbs")
            let verifyFatGoal = appGroup.double(forKey: "widget_goalFat")
            
            let goalsMatch = abs(verifyCalGoal - goals.dailyCalories) < 0.01 &&
                            abs(verifyProtGoal - goals.dailyProtein) < 0.01 &&
                            abs(verifyCarbsGoal - goals.dailyCarbs) < 0.01 &&
                            abs(verifyFatGoal - goals.dailyFat) < 0.01
            
            if goalsMatch {
                print("✅ Goals synced and verified")
            } else {
                print("⚠️ Goals verification failed, retrying...")
                appGroup.set(goals.dailyCalories, forKey: "widget_goalCalories")
                appGroup.set(goals.dailyProtein, forKey: "widget_goalProtein")
                appGroup.set(goals.dailyCarbs, forKey: "widget_goalCarbs")
                appGroup.set(goals.dailyFat, forKey: "widget_goalFat")
                appGroup.synchronize()
            }
        }
        
        // Always sync to standard UserDefaults as fallback
        standardDefaults.set(goals.dailyCalories, forKey: "widget_goalCalories")
        standardDefaults.set(goals.dailyProtein, forKey: "widget_goalProtein")
        standardDefaults.set(goals.dailyCarbs, forKey: "widget_goalCarbs")
        standardDefaults.set(goals.dailyFat, forKey: "widget_goalFat")
        standardDefaults.synchronize()
        
        // Debug logging
        let source = appGroupDefaults != nil ? "App Group + Standard" : "Standard only"
        print("🎯 Syncing goals to widget (\(source)):")
        print("  - Calories goal: \(goals.dailyCalories)")
        print("  - Protein goal: \(goals.dailyProtein)g")
        print("  - Carbs goal: \(goals.dailyCarbs)g")
        print("  - Fat goal: \(goals.dailyFat)g")
        print("  - Also synced consumed: \(dailyLog.totalCalories) cal, \(dailyLog.totalProtein)g protein")
        
        // Request widget reload - ensure sync completes first
        #if canImport(WidgetKit)
        // Use a small delay to ensure synchronize() completes and data is persisted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Widget timeline reload requested (goals + consumed data)")
        }
        #endif
    }
    
    private func syncWidgetDataManually() {
        // Calculate today's totals
        let calories = dailyLog.totalCalories
        let protein = dailyLog.totalProtein
        let carbs = dailyLog.totalCarbs
        let fat = dailyLog.totalFat
        let count = dailyLog.todayFoodItems.count
        
        // Try App Group first, also sync to standard UserDefaults as fallback
        let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        // Sync to App Group if available
        if let appGroup = appGroupDefaults {
            appGroup.set(calories, forKey: "widget_todayCalories")
            appGroup.set(protein, forKey: "widget_todayProtein")
            appGroup.set(carbs, forKey: "widget_todayCarbs")
            appGroup.set(fat, forKey: "widget_todayFat")
            appGroup.set(count, forKey: "widget_foodCount")
            
            // CRITICAL: synchronize() must be called for data to persist
            let syncResult = appGroup.synchronize()
            if !syncResult {
                print("⚠️⚠️⚠️ WARNING: App Group synchronize() returned false!")
            }
            
            // Verify ALL writes succeeded
            let verifyCal = appGroup.double(forKey: "widget_todayCalories")
            let verifyProt = appGroup.double(forKey: "widget_todayProtein")
            let verifyCarbs = appGroup.double(forKey: "widget_todayCarbs")
            let verifyFat = appGroup.double(forKey: "widget_todayFat")
            let verifyCount = appGroup.integer(forKey: "widget_foodCount")
            
            let calMatch = abs(verifyCal - calories) < 0.01
            let protMatch = abs(verifyProt - protein) < 0.01
            let carbsMatch = abs(verifyCarbs - carbs) < 0.01
            let fatMatch = abs(verifyFat - fat) < 0.01
            let countMatch = verifyCount == count
            
            if calMatch && protMatch && carbsMatch && fatMatch && countMatch {
                print("✅ Manually synced to App Group: \(calories) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat, \(count) items")
            } else {
                print("⚠️⚠️⚠️ ERROR: Manual sync verification failed!")
                print("⚠️ Written: \(calories) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat, \(count) items")
                print("⚠️ Read back: \(verifyCal) cal, \(verifyProt)g protein, \(verifyCarbs)g carbs, \(verifyFat)g fat, \(verifyCount) items")
                print("⚠️ Mismatches: calories=\(!calMatch), protein=\(!protMatch), carbs=\(!carbsMatch), fat=\(!fatMatch), count=\(!countMatch)")
                
                // Retry sync if verification failed
                print("🔄 Retrying manual sync...")
                appGroup.set(calories, forKey: "widget_todayCalories")
                appGroup.set(protein, forKey: "widget_todayProtein")
                appGroup.set(carbs, forKey: "widget_todayCarbs")
                appGroup.set(fat, forKey: "widget_todayFat")
                appGroup.set(count, forKey: "widget_foodCount")
                appGroup.synchronize()
            }
        } else {
            print("⚠️⚠️⚠️ WARNING: App Group not available! Widget cannot access this data!")
        }
        
        // Always sync to standard UserDefaults as fallback
        standardDefaults.set(calories, forKey: "widget_todayCalories")
        standardDefaults.set(protein, forKey: "widget_todayProtein")
        standardDefaults.set(carbs, forKey: "widget_todayCarbs")
        standardDefaults.set(fat, forKey: "widget_todayFat")
        standardDefaults.set(count, forKey: "widget_foodCount")
        standardDefaults.synchronize()
        
        let source = appGroupDefaults != nil ? "App Group + Standard" : "Standard only"
        print("🔄 Manually synced widget data to \(source):")
        print("  - Calories: \(calories)")
        print("  - Protein: \(protein)g")
        print("  - Carbs: \(carbs)g")
        print("  - Fat: \(fat)g")
        print("  - Food count: \(count)")
        
        // Request widget reload - ensure sync completes first
        #if canImport(WidgetKit)
        // Use a small delay to ensure synchronize() completes and data is persisted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Widget timeline reload requested (manual sync)")
        }
        #endif
    }
    
}



// MARK: - Add Food View (Legacy - now integrated into CameraMainView)
struct AddFoodView: View {
    @ObservedObject var dailyLog: DailyFoodLog
    @ObservedObject var analysis: NutritionAnalysis
    @StateObject private var cameraPermissions = CameraPermissionManager()
    @StateObject private var foodRecognition = FoodRecognitionService()
    
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Food")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    if cameraPermissions.permissionStatus == .authorized {
                        showingCamera = true
                    } else {
                        cameraPermissions.requestPermission()
                    }
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo of Food")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(foodRecognition.isAnalyzing)
                
                if foodRecognition.isAnalyzing {
                    ProgressView("Analyzing food...")
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .sheet(isPresented: $showingCamera) {
                CameraView(
                    isPresented: $showingCamera,
                    capturedImage: $capturedImage
                ) { image in
                    capturedImage = image
                    foodRecognition.analyzeFoodImage(image)
                }
            }
        }
    }
}

#Preview {
    ContentView(pendingQuickAction: .constant(""))
}
