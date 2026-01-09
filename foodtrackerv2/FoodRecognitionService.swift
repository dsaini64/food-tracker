import Foundation
import UIKit
import Combine

// MARK: - Timeout Helper
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        // Return first completed task and cancel the other
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {
    var localizedDescription: String {
        "Analysis timed out. Please try again."
    }
}

// MARK: - Food Recognition Service
class FoodRecognitionService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var recognitionResult: FoodRecognitionResult?
    @Published var errorMessage: String?
    @Published var analysisProgress: String = ""
    @Published var detectedFoodsCount: Int = 0
    var selectedMealType: FoodItem.MealType? // Selected meal type from UI
    
    private let foodAnalysisService = FoodAnalysisService()
    private var placeholderItemId: UUID? // Track placeholder to replace later
    
    /// Creates a placeholder item immediately (called when capture button is pressed)
    func createPlaceholderItem() {
        let currentTime = Date()
        // Use selected meal type if available, otherwise determine from time
        let mealType = selectedMealType ?? FoodItem.MealType.fromTime(currentTime)
        
        let placeholderItem = FoodItem(
            name: "Processing...",
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 0,
            timestamp: currentTime,
            imageData: nil, // Will be updated when image is captured
            mealType: mealType
        )
        
        // Store placeholder ID to replace later
        placeholderItemId = placeholderItem.id
        
        // Add placeholder immediately to daily log via notification
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("FoodAnalyzed"),
                object: placeholderItem
            )
        }
    }
    
    func analyzeFoodImage(_ image: UIImage, mealType: FoodItem.MealType? = nil) {
        print("🍎 Starting food analysis...")
        print("🍎 Image size: \(image.size)")
        
        // Set analyzing state immediately (already set by button press, but ensure it's set)
        // Use synchronous update since we're likely already on main thread from button action
        if !isAnalyzing {
            isAnalyzing = true
        }
        errorMessage = nil
        if analysisProgress.isEmpty {
            analysisProgress = "Analyzing..."
        }
        
        // If placeholder doesn't exist yet, create it now (fallback)
        if placeholderItemId == nil {
            createPlaceholderItem()
        }
        
        // Helper function to clean up placeholder
        let cleanupPlaceholder = {
            if let placeholderId = self.placeholderItemId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RemoveFoodItem"),
                    object: placeholderId
                )
                self.placeholderItemId = nil
            }
        }
        
        // Start analysis with timeout protection
        Task {
            do {
                print("🍎 Sending image to backend...")
                
                // Add timeout wrapper (30 seconds total timeout - more reasonable)
                let analysis = try await withTimeout(seconds: 30) {
                    try await self.foodAnalysisService.analyzeFoodImage(image)
                }
                
                print("🍎 Received analysis from backend: \(analysis)")
                
                await MainActor.run {
                    // Use selected meal type if available, otherwise use passed mealType or determine from time
                    let finalMealType = self.selectedMealType ?? mealType ?? FoodItem.MealType.fromTime()
                    self.processAnalysis(analysis, image: image, mealType: finalMealType)
                }
            } catch {
                print("🍎 Error during analysis: \(error)")
                
                // Determine error message
                let errorMsg: String
                if error is TimeoutError {
                    errorMsg = "Analysis timed out after 30 seconds. Please check your internet connection and try again."
                } else if let foodError = error as? FoodAnalysisError {
                    errorMsg = foodError.localizedDescription
                } else {
                    errorMsg = "Analysis failed: \(error.localizedDescription)"
                }
                
                await MainActor.run {
                    // Always remove placeholder on error or timeout
                    cleanupPlaceholder()
                    
                    self.errorMessage = errorMsg
                    self.isAnalyzing = false
                    self.analysisProgress = ""
                    
                    // Show error result with more helpful message
                    self.recognitionResult = FoodRecognitionResult(
                        name: "Analysis Failed",
                        confidence: 0.0,
                        calories: 0,
                        protein: 0,
                        carbs: 0,
                        fat: 0,
                        fiber: 0,
                        sugar: 0,
                        sodium: 0,
                        portionSize: nil,
                        underestimatedMultiplier: nil
                    )
                }
            }
        }
    }
    
    /// Returns the multiplier to apply to nutrition values based on portion size
    /// - Parameter portionSize: "small", "medium", or "large" (case-insensitive)
    /// - Returns: Multiplier (0.75 for small, 1.0 for medium, 1.5 for large)
    private static func portionSizeMultiplier(for portionSize: String) -> Double {
        switch portionSize.lowercased() {
        case "small":
            return 0.75  // 25% less than medium
        case "large":
            return 1.5   // 50% more than medium
        case "medium", "":  // Default to medium if empty or unknown
            return 1.0   // Baseline
        default:
            // Unknown portion size - default to medium
            print("⚠️ Unknown portion size '\(portionSize)', defaulting to medium (1.0x)")
            return 1.0
        }
    }
    
    /// Detects if calories are likely underestimated and returns a correction multiplier
    /// This helps catch cases where the backend detects only one ingredient (e.g., broccoli) 
    /// instead of the full dish (e.g., broccoli pasta)
    /// - Parameters:
    ///   - foodName: The detected food name (lowercased)
    ///   - calories: The detected calories
    ///   - mealType: The meal type (breakfast, lunch, dinner, snack)
    ///   - totalFoodsCount: Total number of foods detected in the image
    /// - Returns: Multiplier to apply (1.0 if no correction needed, higher if underestimated)
    private static func detectUnderestimatedCalories(
        foodName: String,
        calories: Double,
        mealType: FoodItem.MealType,
        totalFoodsCount: Int
    ) -> Double {
        // If calories are already reasonable (> 150), no correction needed
        if calories >= 150 {
            return 1.0
        }
        
        // Keywords that suggest a complete meal/dish (not just a single ingredient)
        let mealKeywords = ["pasta", "noodles", "rice", "pizza", "burger", "sandwich", 
                            "wrap", "burrito", "taco", "curry", "stir", "fry", "stir-fry",
                            "casserole", "lasagna", "spaghetti", "fettuccine", "penne",
                            "macaroni", "risotto", "paella", "fried rice", "ramen"]
        
        // Keywords that are typically low-calorie vegetables (often detected alone)
        let vegetableKeywords = ["broccoli", "carrot", "lettuce", "spinach", "cabbage",
                                "celery", "cucumber", "zucchini", "pepper", "onion",
                                "tomato", "mushroom", "asparagus", "green beans"]
        
        // Check if food name contains meal keywords
        let containsMealKeyword = mealKeywords.contains { foodName.contains($0) }
        let containsVegetableKeyword = vegetableKeywords.contains { foodName.contains($0) }
        
        // Case 1: Food name contains meal keywords (e.g., "pasta with broccoli", "broccoli pasta", "chicken rice")
        // but calories are very low - this suggests the backend estimated calories for 
        // just the vegetable/protein, not the full dish
        // Example: "pasta with broccoli" with 76 calories → applies 4x multiplier → 304 calories (more accurate)
        if containsMealKeyword && calories < 150 {
            // For pasta dishes, a typical serving is 300-500 calories
            // If we're getting < 150, we're likely missing the pasta component
            if calories < 50 {
                print("⚠️ Very low calories (\(calories)) for meal-type food '\(foodName)' - applying 5x multiplier")
                return 5.0
            } else if calories < 80 {
                // 76 calories for pasta → 76 * 4 = 304 calories (more reasonable)
                print("⚠️ Low calories (\(calories)) for meal-type food '\(foodName)' - applying 4x multiplier")
                return 4.0
            } else if calories < 120 {
                print("⚠️ Low calories (\(calories)) for meal-type food '\(foodName)' - applying 3x multiplier")
                return 3.0
            } else {
                print("⚠️ Low calories (\(calories)) for meal-type food '\(foodName)' - applying 2x multiplier")
                return 2.0
            }
        }
        
        // Case 2: Single vegetable detection for a main meal (not snack)
        // This suggests the backend detected only the vegetable, not the full dish
        if containsVegetableKeyword && !containsMealKeyword && mealType != .snack {
            if totalFoodsCount == 1 && calories < 80 {
                print("⚠️ Single vegetable detection (\(foodName)) with low calories (\(calories)) for \(mealType.rawValue)")
                print("⚠️ Likely incomplete - applying 3x multiplier (assuming missing main component like pasta/rice)")
                return 3.0
            } else if calories < 100 {
                // Even if multiple foods detected, if a vegetable has very low calories for a main meal, 
                // it might still be underestimated
                print("⚠️ Vegetable detection (\(foodName)) with low calories (\(calories)) for \(mealType.rawValue) - applying 2x multiplier")
                return 2.0
            }
        }
        
        // Case 3: Main meals (not snacks) with very low calories and only one food detected
        // This is suspicious - main meals typically have multiple components or higher calories
        if mealType != .snack && calories < 80 && totalFoodsCount == 1 {
            print("⚠️ Single food detection with low calories (\(calories)) for \(mealType.rawValue) - applying 2.5x multiplier")
            return 2.5
        }
        
        return 1.0
    }
    
    private func processAnalysis(_ analysis: FoodAnalysis, image: UIImage, mealType: FoodItem.MealType) {
        print("🍎 Processing analysis with \(analysis.foods.count) foods")
        
        // Log all detected foods for debugging
        print("🍎 All detected foods:")
        for (index, food) in analysis.foods.enumerated() {
            print("🍎   [\(index + 1)] \(food.name): \(food.calories) cal, portion: \(food.portionSize ?? "unknown"), confidence: \(food.confidence)")
        }
        
        // Check if no foods were returned at all
        guard !analysis.foods.isEmpty else {
            print("🍎 No foods returned from analysis")
            
            // Remove placeholder
            if let placeholderId = placeholderItemId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RemoveFoodItem"),
                    object: placeholderId
                )
                placeholderItemId = nil
            }
            
            self.recognitionResult = FoodRecognitionResult(
                name: "Food Not Detected",
                confidence: 0.0,
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                fiber: 0,
                sugar: 0,
                sodium: 0,
                portionSize: nil,
                underestimatedMultiplier: nil
            )
            self.detectedFoodsCount = 0
            self.isAnalyzing = false
            return
        }
        
        // Calculate total calories from all detected foods (before portion scaling)
        let totalRawCalories = analysis.foods.reduce(0.0) { $0 + $1.calories }
        print("🍎 Total raw calories from all detected foods: \(totalRawCalories)")
        
        // Safety check: If total calories seem unreasonably low for a meal (< 100 cal), warn
        // This helps catch cases where the backend might be detecting only one ingredient
        if totalRawCalories < 100 && mealType != .snack {
            print("⚠️ WARNING: Total calories (\(totalRawCalories)) seems very low for a \(mealType.rawValue.lowercased())")
            print("⚠️ This might indicate incomplete detection (e.g., only detecting broccoli, not pasta)")
            print("⚠️ Detected foods: \(analysis.foods.map { $0.name }.joined(separator: ", "))")
        }
        
        // Compress image once for all food items (shared across all items)
        // This is done outside the parallel processing to avoid redundant compression
        let imageData = image.jpegData(compressionQuality: 0.3)
        let currentTime = Date()
        
        // Process all foods in parallel using TaskGroup
        Task {
            // Filter and validate foods in parallel
            let validFoods = await withTaskGroup(of: FoodRecognitionResult?.self, returning: [FoodRecognitionResult].self) { group in
                var results: [FoodRecognitionResult] = []
        
                // Process each food concurrently
        for (index, food) in analysis.foods.enumerated() {
                    group.addTask {
            print("🍎 Processing food \(index + 1): \(food.name), calories: \(food.calories)")
            
            // Only process real foods (not unidentified)
            if !food.name.lowercased().contains("unidentified") && 
               !food.name.lowercased().contains("unknown") &&
               food.calories > 0 {
                
                let result = FoodRecognitionResult(
                    name: food.name,
                    confidence: food.confidence,
                    calories: food.calories,
                    protein: food.protein,
                    carbs: food.carbs,
                    fat: food.fat,
                    fiber: food.fiber,
                    sugar: 0, // Not provided in new format
                    sodium: 0, // Not provided in new format
                    portionSize: food.portionSize, // Store portion size for scaling
                    underestimatedMultiplier: nil // Will be calculated later when setting recognitionResult
                )
                
                print("🍎 Added valid food: \(result.name), \(result.calories) calories")
                            return result
            } else {
                print("🍎 Skipping unidentified food: \(food.name)")
                            return nil
                        }
                    }
                }
                
                // Collect results as they complete
                for await result in group {
                    if let validResult = result {
                        results.append(validResult)
            }
        }
        
                return results
            }
            
            // Sort by confidence (highest first) to maintain consistent ordering
            let sortedFoods = validFoods.sorted { $0.confidence > $1.confidence }
            
            await MainActor.run {
        // Set the first valid food as the main result for UI display
                if let firstValidFood = sortedFoods.first {
            // Calculate multipliers for the first food to show accurate calories in popup
            let analyzedFood = analysis.foods.first { $0.name == firstValidFood.name }
            let portionSize = analyzedFood?.portionSize?.lowercased() ?? "medium"
            let portionMultiplier = Self.portionSizeMultiplier(for: portionSize)
            let foodNameLower = firstValidFood.name.lowercased()
            let underestimatedMultiplier = Self.detectUnderestimatedCalories(
                foodName: foodNameLower,
                calories: firstValidFood.calories,
                mealType: mealType,
                totalFoodsCount: sortedFoods.count
            )
            let finalMultiplier = portionMultiplier * underestimatedMultiplier
            
            // Create updated recognition result with raw calories but store multipliers
            // The scaledCalories computed property will apply both multipliers
            let scaledResult = FoodRecognitionResult(
                name: firstValidFood.name,
                confidence: firstValidFood.confidence,
                calories: firstValidFood.calories, // Keep raw calories
                protein: firstValidFood.protein,
                carbs: firstValidFood.carbs,
                fat: firstValidFood.fat,
                fiber: firstValidFood.fiber,
                sugar: firstValidFood.sugar,
                sodium: firstValidFood.sodium,
                portionSize: analyzedFood?.portionSize,
                underestimatedMultiplier: underestimatedMultiplier // Store multiplier for scaledCalories
            )
            
            self.recognitionResult = scaledResult
            print("🍎 Set main recognitionResult: \(scaledResult.name) with raw calories: \(scaledResult.calories), scaled calories: \(scaledResult.scaledCalories)")
        } else {
            // No valid foods detected - show "Food not detected" message
            self.recognitionResult = FoodRecognitionResult(
                name: "Food Not Detected",
                confidence: 0.0,
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                fiber: 0,
                sugar: 0,
                sodium: 0,
                portionSize: nil,
                underestimatedMultiplier: nil
            )
            print("🍎 No food detected in image")
        }
        
        // Replace placeholder with actual food items
                if let placeholderId = self.placeholderItemId {
            // Remove placeholder first
            NotificationCenter.default.post(
                name: NSNotification.Name("RemoveFoodItem"),
                object: placeholderId
            )
                    self.placeholderItemId = nil
                }
                
                // Update detected foods count for UI
                self.detectedFoodsCount = sortedFoods.count
        }
        
            // Add all valid foods to daily log in parallel
            await withTaskGroup(of: Void.self) { group in
                for foodResult in sortedFoods {
                    group.addTask {
                        // Find the corresponding AnalyzedFood to get metadata
                        let analyzedFood = analysis.foods.first { analyzedFood in
                            analyzedFood.name == foodResult.name
                        }
                        
                        // Apply portion size scaling to nutrition values
                        // ChatGPT estimates for "medium" by default, so we scale based on actual portion size
                        let portionSize = analyzedFood?.portionSize?.lowercased() ?? "medium"
                        let portionMultiplier = Self.portionSizeMultiplier(for: portionSize)
                        
                        // Check if calories seem unreasonably low for this food type
                        // This helps catch cases where the backend might be detecting only one ingredient
                        let foodNameLower = foodResult.name.lowercased()
                        let underestimatedMultiplier = Self.detectUnderestimatedCalories(
                            foodName: foodNameLower,
                            calories: foodResult.calories,
                            mealType: mealType,
                            totalFoodsCount: sortedFoods.count
                        )
                        
                        // Apply both portion size and underestimation multipliers
                        let finalMultiplier = portionMultiplier * underestimatedMultiplier
                        
                        // Scale all nutrition values based on portion size and underestimation correction
                        let scaledCalories = foodResult.calories * finalMultiplier
                        let scaledProtein = foodResult.protein * finalMultiplier
                        let scaledCarbs = foodResult.carbs * finalMultiplier
                        let scaledFat = foodResult.fat * finalMultiplier
                        let scaledFiber = foodResult.fiber * finalMultiplier
                        let scaledSugar = foodResult.sugar * finalMultiplier
                        let scaledSodium = foodResult.sodium * finalMultiplier
                        
                        print("🍎 Portion scaling: \(portionSize) (multiplier: \(portionMultiplier))")
                        if underestimatedMultiplier > 1.0 {
                            print("⚠️ Applied underestimation correction: \(underestimatedMultiplier)x (detected low calories for \(foodResult.name))")
                        }
                        print("🍎 Original: \(foodResult.calories) cal → Scaled: \(scaledCalories) cal (final multiplier: \(finalMultiplier))")
                        
                        // Create FoodItem with scaled values
                        // All items use the same compressed image data and timestamp
                        let foodItem = FoodItem(
                            name: foodResult.name,
                            calories: scaledCalories,
                            protein: scaledProtein,
                            carbs: scaledCarbs,
                            fat: scaledFat,
                            fiber: scaledFiber,
                            sugar: scaledSugar,
                            sodium: scaledSodium,
                            timestamp: currentTime,
                            imageData: imageData,
                            mealType: mealType,
                            ingredients: analyzedFood?.ingredients,
                            location: nil, // Could be determined from device location in future
                            portionSize: analyzedFood?.portionSize,
                            macroGuess: analyzedFood?.macroGuess
                        )
                        
                        // Post notification on main thread for thread safety
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("FoodAnalyzed"),
                                object: foodItem
                            )
                        }
                    }
                }
                
                // Wait for all items to be added
                await group.waitForAll()
            }
            
            await MainActor.run {
                print("🍎 Added \(sortedFoods.count) foods to daily log (processed in parallel)")
        self.isAnalyzing = false
            }
        }
    }
    
    // Legacy method - kept for backward compatibility but now handled in processAnalysis
    private func addToDailyLog(_ result: FoodRecognitionResult, image: UIImage, mealType: FoodItem.MealType) {
        // Convert image to data for storage with lower quality to reduce memory usage
        let imageData = image.jpegData(compressionQuality: 0.3)
        
        // Use the passed meal type (which should be the selected one from UI)
        let currentTime = Date()
        
        print("🍎 Using meal type: \(mealType.rawValue) for time: \(currentTime)")
        
        // Create a FoodItem from the result
        let foodItem = FoodItem(
            name: result.name,
            calories: result.calories,
            protein: result.protein,
            carbs: result.carbs,
            fat: result.fat,
            fiber: result.fiber,
            sugar: result.sugar,
            sodium: result.sodium,
            timestamp: currentTime,
            imageData: imageData,
            mealType: mealType
        )
        
        // Add to daily log (this would need to be injected or accessed via a shared instance)
        // For now, we'll use a notification to update the daily log
        NotificationCenter.default.post(
            name: NSNotification.Name("FoodAnalyzed"),
            object: foodItem
        )
    }
    
}

// MARK: - Food Recognition Result
struct FoodRecognitionResult {
    let name: String
    let confidence: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let portionSize: String? // Store portion size for scaling calculation
    let underestimatedMultiplier: Double? // Store underestimation multiplier if applied
    
    var confidencePercentage: Int {
        Int(confidence * 100)
    }
    
    // Calculate scaled values based on portion size AND underestimation multiplier
    // This ensures the popup shows the same calories that get saved
    var scaledCalories: Double {
        let portionMultiplier = Self.portionSizeMultiplier(for: portionSize ?? "medium")
        let underestimationMultiplier = underestimatedMultiplier ?? 1.0
        let finalMultiplier = portionMultiplier * underestimationMultiplier
        return calories * finalMultiplier
    }
    
    var scaledProtein: Double {
        let portionMultiplier = Self.portionSizeMultiplier(for: portionSize ?? "medium")
        let underestimationMultiplier = underestimatedMultiplier ?? 1.0
        let finalMultiplier = portionMultiplier * underestimationMultiplier
        return protein * finalMultiplier
    }
    
    private static func portionSizeMultiplier(for portionSize: String) -> Double {
        switch portionSize.lowercased() {
        case "small":
            return 0.75
        case "large":
            return 1.5
        case "medium", "":
            return 1.0
        default:
            return 1.0
        }
    }
}

