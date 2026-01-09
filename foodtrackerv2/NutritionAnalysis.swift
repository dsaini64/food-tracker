import Foundation
import SwiftUI
import Combine

// MARK: - Nutrition Analysis
class NutritionAnalysis: ObservableObject {
    @Published var dailyLog: DailyFoodLog
    @Published var goals: NutritionGoals
    private var cancellables = Set<AnyCancellable>()
    
    init(dailyLog: DailyFoodLog, goals: NutritionGoals = .defaultGoals) {
        self.dailyLog = dailyLog
        self.goals = goals
        
        // Forward changes from dailyLog to trigger NutritionAnalysis updates
        dailyLog.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Progress Calculations
    var caloriesProgress: Double {
        guard goals.dailyCalories > 0 else { return 0 }
        return min(dailyLog.totalCalories / goals.dailyCalories, 1.0)
    }
    
    var proteinProgress: Double {
        guard goals.dailyProtein > 0 else { return 0 }
        // If protein is 0 or essentially 0 (less than 0.01g), return exactly 0 to avoid any progress bar
        guard dailyLog.totalProtein >= 0.01 else { return 0 }
        // Round to 2 decimal places to avoid floating point precision issues
        let roundedProtein = round(dailyLog.totalProtein * 100) / 100
        guard roundedProtein >= 0.01 else { return 0 }
        let calculatedProgress = min(roundedProtein / goals.dailyProtein, 1.0)
        // Ensure progress is exactly 0 if it's less than 0.0001 (essentially zero)
        return calculatedProgress < 0.0001 ? 0 : calculatedProgress
    }
    
    var carbsProgress: Double {
        guard goals.dailyCarbs > 0 else { return 0 }
        // If carbs is 0 or essentially 0 (less than 0.01g), return exactly 0 to avoid any progress bar
        guard dailyLog.totalCarbs >= 0.01 else { return 0 }
        // Round to 2 decimal places to avoid floating point precision issues
        let roundedCarbs = round(dailyLog.totalCarbs * 100) / 100
        guard roundedCarbs >= 0.01 else { return 0 }
        let calculatedProgress = min(roundedCarbs / goals.dailyCarbs, 1.0)
        // Ensure progress is exactly 0 if it's less than 0.0001 (essentially zero)
        return calculatedProgress < 0.0001 ? 0 : calculatedProgress
    }
    
    var fatProgress: Double {
        guard goals.dailyFat > 0 else { return 0 }
        // If fat is 0 or essentially 0 (less than 0.01g), return exactly 0 to avoid any progress bar
        guard dailyLog.totalFat >= 0.01 else { return 0 }
        // Round to 2 decimal places to avoid floating point precision issues
        let roundedFat = round(dailyLog.totalFat * 100) / 100
        guard roundedFat >= 0.01 else { return 0 }
        let calculatedProgress = min(roundedFat / goals.dailyFat, 1.0)
        // Ensure progress is exactly 0 if it's less than 0.0001 (essentially zero)
        return calculatedProgress < 0.0001 ? 0 : calculatedProgress
    }
    
    // MARK: - Improvement Suggestions
    func generateImprovementSuggestions() -> [String] {
        var suggestions: [String] = []
        
        // Calorie-based suggestions
        if dailyLog.totalCalories < goals.dailyCalories * 0.8 {
            suggestions.append("Consider adding healthy snacks to meet your calorie goals")
        } else if dailyLog.totalCalories > goals.dailyCalories * 1.2 {
            suggestions.append("Try reducing portion sizes or choosing lower-calorie options")
        }
        
        // Protein suggestions
        if dailyLog.totalProtein < goals.dailyProtein * 0.7 {
            suggestions.append("Add more lean proteins like chicken, fish, or legumes")
        }
        
        // Meal balance suggestions
        let mealTypes = FoodItem.MealType.allCases
        let emptyMeals = mealTypes.filter { dailyLog.getFoodItems(for: $0).isEmpty }
        
        if emptyMeals.contains(.breakfast) {
            suggestions.append("Don't skip breakfast - it kickstarts your metabolism")
        }
        
        if emptyMeals.contains(.lunch) {
            suggestions.append("A balanced lunch helps maintain energy throughout the day")
        }
        
        if emptyMeals.contains(.dinner) {
            suggestions.append("A nutritious dinner supports overnight recovery")
        }
        
        // Hydration reminder
        suggestions.append("Remember to stay hydrated throughout the day")
        
        return suggestions.isEmpty ? ["Keep up the great work!"] : suggestions
    }
    
    // MARK: - Daily Summary
    func generateDailySummary() -> DailySummary {
        let suggestions = generateImprovementSuggestions()
        let mealBreakdown = generateMealBreakdown()
        
        return DailySummary(
            totalCalories: dailyLog.totalCalories,
            totalProtein: dailyLog.totalProtein,
            totalCarbs: dailyLog.totalCarbs,
            totalFat: dailyLog.totalFat,
            mealBreakdown: mealBreakdown,
            suggestions: suggestions,
            goalsMet: calculateGoalsMet()
        )
    }
    
    private func generateMealBreakdown() -> [MealBreakdown] {
        return FoodItem.MealType.allCases.map { mealType in
            let items = dailyLog.getFoodItems(for: mealType)
            let calories = items.reduce(0) { $0 + $1.calories }
            
            return MealBreakdown(
                mealType: mealType,
                calories: calories,
                itemCount: items.count
            )
        }
    }
    
    private func calculateGoalsMet() -> [String: Bool] {
        return [
            "Calories": dailyLog.totalCalories >= goals.dailyCalories * 0.8 && dailyLog.totalCalories <= goals.dailyCalories * 1.2,
            "Protein": dailyLog.totalProtein >= goals.dailyProtein * 0.7
        ]
    }
}

// MARK: - Daily Summary Model
struct DailySummary {
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let mealBreakdown: [MealBreakdown]
    let suggestions: [String]
    let goalsMet: [String: Bool]
}

struct MealBreakdown {
    let mealType: FoodItem.MealType
    let calories: Double
    let itemCount: Int
}
