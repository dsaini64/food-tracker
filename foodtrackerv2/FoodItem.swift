import Foundation
import SwiftUI
import Combine
import WidgetKit

// MARK: - Food Item Model
struct FoodItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let timestamp: Date
    let mealType: MealType
    // Additional metadata for pattern analysis
    let ingredients: [String]?
    let location: String? // "home" or "outside"
    let portionSize: String? // "small", "medium", "large"
    let macroGuess: String? // "carb-heavy", "protein-rich", "fat-heavy", "balanced"
    
    // imageData is NOT stored in UserDefaults - it's stored separately in file system
    // This computed property loads from file system when accessed
    var imageData: Data? {
        get {
            return ImageStorage.shared.loadImage(for: id)
        }
        nonmutating set {
            if let data = newValue {
                ImageStorage.shared.saveImage(data, for: id)
            } else {
                ImageStorage.shared.deleteImage(for: id)
            }
        }
    }
    
    /// Returns the meal type for this item
    /// Uses the stored mealType property which reflects the user's selection
    var categorizedMealType: MealType {
        return mealType
    }
    
    // Custom initializer with default values for new fields
    init(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        sodium: Double,
        timestamp: Date,
        imageData: Data?,
        mealType: MealType,
        ingredients: [String]? = nil,
        location: String? = nil,
        portionSize: String? = nil,
        macroGuess: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.timestamp = timestamp
        self.mealType = mealType
        self.ingredients = ingredients
        self.location = location
        self.portionSize = portionSize
        self.macroGuess = macroGuess
        
        // Store image data separately in file system (NOT in UserDefaults)
        // Save asynchronously to avoid blocking initialization
        if let data = imageData {
            // Save immediately but asynchronously - don't wait for it
            ImageStorage.shared.saveImage(data, for: self.id)
        }
    }
    
    // Custom Codable implementation to exclude imageData from UserDefaults
    // imageData is automatically excluded since it's a computed property
    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat, fiber, sugar, sodium, timestamp, mealType
        case ingredients, location, portionSize, macroGuess
        case imageData // Include for migration from old format
    }
    
    // Custom decoder to handle migration from old format (with imageData in UserDefaults)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all stored properties
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Double.self, forKey: .calories)
        protein = try container.decode(Double.self, forKey: .protein)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fat = try container.decode(Double.self, forKey: .fat)
        fiber = try container.decode(Double.self, forKey: .fiber)
        sugar = try container.decode(Double.self, forKey: .sugar)
        sodium = try container.decode(Double.self, forKey: .sodium)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mealType = try container.decode(MealType.self, forKey: .mealType)
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        portionSize = try container.decodeIfPresent(String.self, forKey: .portionSize)
        macroGuess = try container.decodeIfPresent(String.self, forKey: .macroGuess)
        
        // Migrate imageData from old format (if present) to file system
        if let oldImageData = try? container.decodeIfPresent(Data.self, forKey: .imageData) {
            // Save to file system and remove from UserDefaults
            ImageStorage.shared.saveImage(oldImageData, for: id)
            print("🔄 Migrated image data for item \(id) from UserDefaults to file system")
        }
    }
    
    // Custom encoder to exclude imageData from UserDefaults
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode all stored properties (excluding imageData)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(calories, forKey: .calories)
        try container.encode(protein, forKey: .protein)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(fat, forKey: .fat)
        try container.encode(fiber, forKey: .fiber)
        try container.encode(sugar, forKey: .sugar)
        try container.encode(sodium, forKey: .sodium)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(mealType, forKey: .mealType)
        try container.encodeIfPresent(ingredients, forKey: .ingredients)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(portionSize, forKey: .portionSize)
        try container.encodeIfPresent(macroGuess, forKey: .macroGuess)
        
        // imageData is NOT encoded - it's stored separately in file system
    }
    
    enum MealType: String, CaseIterable, Codable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"
        
        var emoji: String {
            switch self {
            case .breakfast: return "🌅"
            case .lunch: return "☀️"
            case .dinner: return "🌙"
            case .snack: return "🍎"
            }
        }
        
        /// Determines meal type based on the time of day
        /// - Breakfast: 4:00 AM - 10:00 AM
        /// - Lunch: 10:00 AM - 3:30 PM
        /// - Dinner: 5:00 PM - 12:00 AM (midnight)
        /// - Snack: All other times (12:00 AM - 4:00 AM and 3:30 PM - 5:00 PM)
        static func fromTime(_ date: Date = Date()) -> MealType {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            let timeInMinutes = hour * 60 + minute
            
            // Breakfast: 4:00 AM - 10:00 AM (240-600 minutes)
            // 4:00 AM = 240 minutes, 10:00 AM = 600 minutes
            if timeInMinutes >= 240 && timeInMinutes < 600 {
                return .breakfast
            }
            
            // Lunch: 10:00 AM - 3:30 PM (600-930 minutes)
            // 10:00 AM = 600 minutes, 3:30 PM = 15:30 = 930 minutes
            if timeInMinutes >= 600 && timeInMinutes < 930 {
                return .lunch
            }
            
            // Dinner: 5:00 PM - 12:00 AM (1020-1440 minutes)
            // 5:00 PM = 17:00 = 1020 minutes, 12:00 AM (midnight) = 24:00 = 1440 minutes
            if timeInMinutes >= 1020 && timeInMinutes < 1440 {
                return .dinner
            }
            
            // Snack: All other times
            // 12:00 AM - 4:00 AM (0-240 minutes) or 3:30 PM - 5:00 PM (930-1020 minutes)
            return .snack
        }
    }
    
    // Hashable conformance - use id since it's unique
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Image Storage Manager
class ImageStorage {
    static let shared = ImageStorage()
    
    private let fileManager = FileManager.default
    private let imageSaveQueue = DispatchQueue(label: "com.foodtracker.imagesave", qos: .utility)
    private var _imagesDirectory: URL?
    
    private var imagesDirectory: URL {
        if let cached = _imagesDirectory {
            return cached
        }
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesPath = documentsPath.appendingPathComponent("FoodImages")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: imagesPath.path) {
            try? fileManager.createDirectory(at: imagesPath, withIntermediateDirectories: true)
        }
        
        _imagesDirectory = imagesPath
        return imagesPath
    }
    
    private init() {}
    
    func saveImage(_ data: Data, for id: UUID) {
        // Save asynchronously to avoid blocking
        let dir = imagesDirectory // Cache directory URL on current thread
        imageSaveQueue.async {
            let fileURL = dir.appendingPathComponent("\(id.uuidString).jpg")
            try? data.write(to: fileURL)
        }
    }
    
    func loadImage(for id: UUID) -> Data? {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        // Use synchronous read for immediate access, but it's fast for small files
        return try? Data(contentsOf: fileURL)
    }
    
    func deleteImage(for id: UUID) {
        let dir = imagesDirectory // Cache directory URL on current thread
        imageSaveQueue.async {
            let fileURL = dir.appendingPathComponent("\(id.uuidString).jpg")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    func cleanupOldImages(keeping itemIds: Set<UUID>) {
        let dir = imagesDirectory // Cache directory URL on current thread
        imageSaveQueue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                return
            }
            
            for fileURL in files {
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                if let fileId = UUID(uuidString: fileName), !itemIds.contains(fileId) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
}

// MARK: - Daily Food Log
class DailyFoodLog: ObservableObject {
    // Store ALL food items for historical trends (week/month/year)
    @Published var foodItems: [FoodItem] = [] {
        didSet {
            // Auto-save whenever foodItems changes
            saveFoodItems()
            // Sync widget data with debouncing to prevent rapid syncs
            debouncedSyncWidgetData()
            // Clean up very old data (older than 1 year) to prevent storage bloat
            cleanupOldData()
        }
    }
    @Published var currentDate: Date = Date()
    
    private let calendar = Calendar.current
    private var currentDayString: String = ""
    private let foodItemsKey = "SavedFoodItems"
    
    // Debounce timer for widget sync to prevent rapid syncs when multiple foods are added
    private var syncWidgetTimer: Timer?
    
    init() {
        // Initialize current day string
        updateCurrentDayString()
        // Load saved food items before checking for new day
        loadFoodItems()
        checkForNewDay()
        
        // Sync existing data to widget on initialization
        // Use a small delay to ensure computed properties are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncWidgetData()
        }
        
        print("🚀 DailyFoodLog initialized with \(foodItems.count) total items")
        print("📅 Today's items will be synced after computed properties are ready")
    }
    
    // Computed property to get only today's food items, sorted by timestamp (latest first)
    var todayFoodItems: [FoodItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        let todayString = formatter.string(from: Date())
        
        return foodItems.filter { item in
            let itemDayString = formatter.string(from: item.timestamp)
            return itemDayString == todayString
        }
        .sorted { $0.timestamp > $1.timestamp } // Latest timestamp first (top), earliest last (bottom)
    }
    
    // Daily totals - only count today's items
    var totalCalories: Double {
        todayFoodItems.reduce(0) { $0 + $1.calories }
    }
    
    var totalProtein: Double {
        todayFoodItems.reduce(0) { $0 + $1.protein }
    }
    
    var totalCarbs: Double {
        todayFoodItems.reduce(0) { $0 + $1.carbs }
    }
    
    var totalFat: Double {
        todayFoodItems.reduce(0) { $0 + $1.fat }
    }
    
    func addFoodItem(_ item: FoodItem) {
        // Check for new day first (this will reset if needed)
        checkForNewDay()
        
        // Verify the item is from today before adding
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        
        let itemDayString = formatter.string(from: item.timestamp)
        let todayString = formatter.string(from: Date())
        
        // Only add items from today
        if itemDayString == todayString {
            foodItems.append(item)
            print("✅ Added food item: \(item.name) on \(itemDayString)")
            print("📊 Total items in log: \(foodItems.count), Today's items: \(todayFoodItems.count)")
            print("📊 New totals - Calories: \(totalCalories), Protein: \(totalProtein)g, Carbs: \(totalCarbs)g, Fat: \(totalFat)g")
            // Note: syncWidgetData() is automatically called in foodItems didSet
            
            // Sync to HealthKit if enabled
            HealthKitManager.shared.saveFoodItem(item)
            
            // Post notification to trigger pattern summary regeneration
            NotificationCenter.default.post(name: NSNotification.Name("FoodItemAdded"), object: nil)
        } else {
            print("⚠️ Skipping item from different day: \(itemDayString) (today is \(todayString))")
            print("⚠️ Item timestamp: \(item.timestamp), Today: \(Date())")
        }
    }
    
    func removeFoodItem(_ item: FoodItem) {
        // Delete associated image file
        ImageStorage.shared.deleteImage(for: item.id)
        foodItems.removeAll { $0.id == item.id }
        
        // Remove from HealthKit if enabled
        HealthKitManager.shared.deleteFoodItem(item)
        
        // Post notification to trigger pattern summary regeneration
        NotificationCenter.default.post(name: NSNotification.Name("FoodItemRemoved"), object: nil)
    }
    
    func updateFoodItemMealType(_ item: FoodItem, to newMealType: FoodItem.MealType) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else {
            print("⚠️ Food item not found for meal type update")
            return
        }
        
        // Load image data before creating new item
        let imageData = item.imageData
        
        // Create a new FoodItem with updated meal type (since FoodItem is immutable)
        let updatedItem = FoodItem(
            name: item.name,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            fiber: item.fiber,
            sugar: item.sugar,
            sodium: item.sodium,
            timestamp: item.timestamp,
            imageData: imageData,
            mealType: newMealType,
            ingredients: item.ingredients,
            location: item.location,
            portionSize: item.portionSize,
            macroGuess: item.macroGuess,
            id: item.id // Preserve the same ID so image data is maintained
        )
        
        foodItems[index] = updatedItem
        print("✅ Updated meal type for '\(item.name)' to \(newMealType.rawValue)")
        
        // Post notification to trigger pattern summary regeneration
        NotificationCenter.default.post(name: NSNotification.Name("FoodItemMealTypeUpdated"), object: nil)
    }
    
    func updateFoodItem(_ item: FoodItem, name: String, calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, sodium: Double) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else {
            print("⚠️ Food item not found for update")
            return
        }
        
        // Load image data before creating new item
        let imageData = item.imageData
        
        // Create a new FoodItem with updated values (since FoodItem is immutable)
        let updatedItem = FoodItem(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            timestamp: item.timestamp,
            imageData: imageData,
            mealType: item.mealType,
            ingredients: item.ingredients,
            location: item.location,
            portionSize: item.portionSize,
            macroGuess: item.macroGuess,
            id: item.id // Preserve the same ID so image data is maintained
        )
        
        foodItems[index] = updatedItem
        print("✅ Updated food item '\(name)' with new macros")
        
        // Post notification to trigger pattern summary regeneration
        NotificationCenter.default.post(name: NSNotification.Name("FoodItemMealTypeUpdated"), object: nil)
    }
    
    func updateFoodItemTimestamp(_ item: FoodItem, to newTimestamp: Date) {
        guard let index = foodItems.firstIndex(where: { $0.id == item.id }) else {
            print("⚠️ Food item not found for timestamp update")
            return
        }
        
        // Load image data before creating new item
        let imageData = item.imageData
        
        // Create a new FoodItem with updated timestamp (since FoodItem is immutable)
        let updatedItem = FoodItem(
            name: item.name,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            fiber: item.fiber,
            sugar: item.sugar,
            sodium: item.sodium,
            timestamp: newTimestamp,
            imageData: imageData,
            mealType: item.mealType,
            ingredients: item.ingredients,
            location: item.location,
            portionSize: item.portionSize,
            macroGuess: item.macroGuess,
            id: item.id // Preserve the same ID so image data is maintained
        )
        
        foodItems[index] = updatedItem
        
        // Reorder foodItems array by timestamp (latest first) to maintain chronological order
        foodItems.sort { $0.timestamp > $1.timestamp }
        
        print("✅ Updated food item '\(item.name)' timestamp to \(newTimestamp) and reordered list")
        
        // Post notification to trigger pattern summary regeneration
        NotificationCenter.default.post(name: NSNotification.Name("FoodItemMealTypeUpdated"), object: nil)
    }
    
    func getFoodItems(for mealType: FoodItem.MealType) -> [FoodItem] {
        // Use categorizedMealType to ensure correct categorization based on timestamp
        // Return only today's items for meal type
        return todayFoodItems.filter { $0.categorizedMealType == mealType }
    }
    
    /// Recategorizes all food items based on their timestamp
    /// This is useful if meal type categorization logic changes
    func recategorizeFoodItems() {
        // Note: Since FoodItem is immutable, we'd need to recreate items
        // For now, this is a placeholder - items are categorized at creation time
        // If needed, we could implement a method that recreates items with correct meal types
    }
    
    private func updateCurrentDayString() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current // Use local timezone
        formatter.locale = Locale.current
        currentDayString = formatter.string(from: Date())
    }
    
    func checkForNewDay() {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current // Use local timezone
        formatter.locale = Locale.current
        let todayString = formatter.string(from: today)
        
        // Only update if we're actually on a different day
        // Note: We DON'T delete historical data - it's needed for trends!
        if todayString != currentDayString {
            print("🔄 New day detected! Keeping historical data for trends.")
            print("🔄 Previous day: \(currentDayString), Current day: \(todayString)")
            print("🔄 Timezone: \(TimeZone.current.identifier)")
            print("📊 Total food items in history: \(foodItems.count)")
            print("📅 Today's food items: \(todayFoodItems.count)")
            currentDate = today
            currentDayString = todayString
            // Clean up old data (older than 1 year) to prevent storage bloat
            cleanupOldData()
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Saves food items to UserDefaults
    private func saveFoodItems() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encoded = try encoder.encode(foodItems)
            UserDefaults.standard.set(encoded, forKey: foodItemsKey)
            print("💾 Saved \(foodItems.count) food items to persistent storage")
        } catch {
            print("❌ Error saving food items: \(error.localizedDescription)")
        }
    }
    
    /// Loads food items from UserDefaults
    private func loadFoodItems() {
        guard let data = UserDefaults.standard.data(forKey: foodItemsKey) else {
            print("📭 No saved food items found")
            return
        }
        
        // Check data size - if it's too large (>3MB), it likely contains image data
        // Clear it and let the migration handle it on next save
        let dataSizeMB = Double(data.count) / (1024 * 1024)
        if dataSizeMB > 3.0 {
            print("⚠️ UserDefaults data is too large (\(String(format: "%.2f", dataSizeMB)) MB) - likely contains image data")
            print("🔄 Clearing corrupted data. Images will be migrated to file system on next save.")
            UserDefaults.standard.removeObject(forKey: foodItemsKey)
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedItems = try decoder.decode([FoodItem].self, from: data)
            
            // Load ALL items (not just today's) - needed for trends
            // Sort by timestamp (latest first) to maintain chronological order
            foodItems = loadedItems.sorted { $0.timestamp > $1.timestamp }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            formatter.locale = Locale.current
            let todayString = formatter.string(from: Date())
            let todayItems = loadedItems.filter { item in
                let itemDayString = formatter.string(from: item.timestamp)
                return itemDayString == todayString
            }
            let todayCount = todayItems.count
            
            // Calculate today's totals for immediate logging
            let todayCalories = todayItems.reduce(0.0) { $0 + $1.calories }
            let todayProtein = todayItems.reduce(0.0) { $0 + $1.protein }
            let todayCarbs = todayItems.reduce(0.0) { $0 + $1.carbs }
            let todayFat = todayItems.reduce(0.0) { $0 + $1.fat }
            
            print("📂 Loaded \(loadedItems.count) total food items from history")
            print("📅 Today's food items: \(todayCount)")
            print("📊 Today's totals - Calories: \(todayCalories), Protein: \(todayProtein)g, Carbs: \(todayCarbs)g, Fat: \(todayFat)g")
            print("📊 Historical items available for trends: \(loadedItems.count - todayCount)")
            
            // Force immediate sync after loading (didSet will also trigger, but this ensures it happens)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.syncWidgetData()
            }
        } catch {
            print("❌ Error loading food items: \(error.localizedDescription)")
            print("🔄 Clearing corrupted data. Images will be migrated to file system on next save.")
            // If decoding fails, clear the corrupted data
            UserDefaults.standard.removeObject(forKey: foodItemsKey)
        }
    }
    
    /// Cleans up food items older than 1 year to prevent storage bloat
    private func cleanupOldData() {
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let beforeCount = foodItems.count
        let filteredItems = foodItems.filter { $0.timestamp >= oneYearAgo }
        
        // Only update if items were actually removed to avoid unnecessary didSet triggers
        if filteredItems.count != beforeCount {
            // Clean up orphaned images for deleted items
            let remainingIds = Set(filteredItems.map { $0.id })
            ImageStorage.shared.cleanupOldImages(keeping: remainingIds)
            
            // Sort by timestamp (latest first) to maintain chronological order
            foodItems = filteredItems.sorted { $0.timestamp > $1.timestamp }
            print("🧹 Cleaned up \(beforeCount - filteredItems.count) food items older than 1 year")
        }
    }
    
    /// Syncs today's data to UserDefaults for widget access
    // Debounced version that waits for rapid changes to settle before syncing
    private func debouncedSyncWidgetData() {
        // Cancel any pending sync
        syncWidgetTimer?.invalidate()
        
        // Schedule a new sync after a short delay (200ms)
        // This batches rapid additions (like adding multiple saved foods) into a single sync
        syncWidgetTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.syncWidgetData()
        }
    }
    
    private func syncWidgetData() {
        // Calculate today's totals
        let calories = totalCalories
        let protein = totalProtein
        let carbs = totalCarbs
        let fat = totalFat
        let count = todayFoodItems.count
        
        // Try App Group first - THIS IS CRITICAL for widgets!
        // Widget extensions CANNOT access the main app's UserDefaults.standard
        // They can ONLY access App Groups
        let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        // CRITICAL: Always sync to App Group if available
        // Widget extensions can ONLY read from App Groups, not standard UserDefaults
        if let appGroup = appGroupDefaults {
            // Write all values
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
            
            // Immediately verify ALL writes succeeded (check all macros, not just calories/protein)
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
                print("✅ Synced to App Group: \(calories) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat, \(count) items")
                print("✅ Verification passed: All macros match")
            } else {
                print("⚠️⚠️⚠️ ERROR: App Group write verification failed!")
                print("⚠️ Written: \(calories) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat, \(count) items")
                print("⚠️ Read back: \(verifyCal) cal, \(verifyProt)g protein, \(verifyCarbs)g carbs, \(verifyFat)g fat, \(verifyCount) items")
                print("⚠️ Mismatches: calories=\(!calMatch), protein=\(!protMatch), carbs=\(!carbsMatch), fat=\(!fatMatch), count=\(!countMatch)")
                
                // Retry sync if verification failed
                print("🔄 Retrying sync...")
                appGroup.set(calories, forKey: "widget_todayCalories")
                appGroup.set(protein, forKey: "widget_todayProtein")
                appGroup.set(carbs, forKey: "widget_todayCarbs")
                appGroup.set(fat, forKey: "widget_todayFat")
                appGroup.set(count, forKey: "widget_foodCount")
                appGroup.synchronize()
            }
        } else {
            print("⚠️⚠️⚠️ WARNING: App Group not available! Widget cannot access this data!")
            print("⚠️⚠️⚠️ Configure App Groups in Xcode: Signing & Capabilities > App Groups")
            print("⚠️⚠️⚠️ Add '\(AppGroupConstants.appGroupIdentifier)' to both app and widget targets")
            print("⚠️⚠️⚠️ Check entitlements file matches: \(AppGroupConstants.appGroupIdentifier)")
        }
        
        // Also sync to standard UserDefaults (for debugging, but widget can't read this)
        standardDefaults.set(calories, forKey: "widget_todayCalories")
        standardDefaults.set(protein, forKey: "widget_todayProtein")
        standardDefaults.set(carbs, forKey: "widget_todayCarbs")
        standardDefaults.set(fat, forKey: "widget_todayFat")
        standardDefaults.set(count, forKey: "widget_foodCount")
        standardDefaults.synchronize()
        
        // Debug logging
        let source = appGroupDefaults != nil ? "App Group + Standard" : "Standard only (WIDGET WON'T WORK!)"
        print("🔄 Syncing widget data to \(source):")
        print("  - Calories: \(calories)")
        print("  - Protein: \(protein)g")
        print("  - Carbs: \(carbs)g")
        print("  - Fat: \(fat)g")
        print("  - Food count: \(count)")
        
        // Request widget reload - ensure sync completes first
        // Use a small delay to ensure synchronize() completes and data is persisted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Widget timeline reload requested (after sync delay)")
        }
        
        // Final verification of all macros (for debugging)
        if let appGroup = appGroupDefaults {
            let verifyCalories = appGroup.double(forKey: "widget_todayCalories")
            let verifyProtein = appGroup.double(forKey: "widget_todayProtein")
            let verifyCarbs = appGroup.double(forKey: "widget_todayCarbs")
            let verifyFat = appGroup.double(forKey: "widget_todayFat")
            let verifyCount = appGroup.integer(forKey: "widget_foodCount")
            
            let allMatch = abs(verifyCalories - calories) < 0.01 &&
                          abs(verifyProtein - protein) < 0.01 &&
                          abs(verifyCarbs - carbs) < 0.01 &&
                          abs(verifyFat - fat) < 0.01 &&
                          verifyCount == count
            
            if allMatch {
                print("✅ Final verification passed: All macros synced correctly")
            } else {
                print("⚠️ WARNING: Final verification failed!")
                print("⚠️ Expected: \(calories) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat, \(count) items")
                print("⚠️ Actual: \(verifyCalories) cal, \(verifyProtein)g protein, \(verifyCarbs)g carbs, \(verifyFat)g fat, \(verifyCount) items")
            }
        }
    }
}

// MARK: - Nutrition Goals
struct NutritionGoals: Equatable {
    let dailyCalories: Double
    let dailyProtein: Double
    let dailyCarbs: Double
    let dailyFat: Double
    
    static let defaultGoals = NutritionGoals(
        dailyCalories: 2000,
        dailyProtein: 150,
        dailyCarbs: 250,
        dailyFat: 65
    )
}
