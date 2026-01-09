// Test file to check for compilation errors
import Foundation

// Note: This file contains test functions but does not execute them automatically
// to avoid top-level expression errors. Call these functions from main.swift or tests.

// Test function to verify compilation
func runCompilationTests() {
    // Test FoodItem creation
    let foodItem = FoodItem(
        name: "Test Apple",
        calories: 95,
        protein: 0.5,
        carbs: 25,
        fat: 0.3,
        fiber: 4,
        sugar: 19,
        sodium: 2,
        timestamp: Date(),
        imageData: nil,
        mealType: .snack,
    )
    print("FoodItem created successfully: \(foodItem.name)")

    // Test DailyFoodLog
    let dailyLog = DailyFoodLog()
    dailyLog.addFoodItem(foodItem)
    print("DailyFoodLog created successfully with \(dailyLog.foodItems.count) items")

    // Test NutritionAnalysis
    let analysis = NutritionAnalysis(dailyLog: dailyLog)
    print("NutritionAnalysis created successfully")

    // Test MealType enum
    let mealType = FoodItem.MealType.breakfast
    print("MealType: \(mealType.rawValue), Emoji: \(mealType.emoji)")

    // Test FoodRecognitionService (if UIKit is available)
    #if canImport(UIKit)
    let recognitionService = FoodRecognitionService()
    print("FoodRecognitionService created successfully")
    #endif

    print("All tests passed! ✅")
}
