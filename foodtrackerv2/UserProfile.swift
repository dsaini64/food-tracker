//
//  UserProfile.swift
//  foodtrackerv2
//
//  Created by Divakar Saini on 10/13/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - User Profile Model
class UserProfile: ObservableObject {
    
    @Published var age: Int {
        didSet {
            UserDefaults.standard.set(age, forKey: "userAge")
        }
    }
    
    @Published var gender: Gender {
        didSet {
            UserDefaults.standard.set(gender.rawValue, forKey: "userGender")
        }
    }
    
    @Published var height: Double {
        didSet {
            UserDefaults.standard.set(height, forKey: "userHeight")
        }
    }
    
    @Published var weight: Double {
        didSet {
            UserDefaults.standard.set(weight, forKey: "userWeight")
        }
    }
    
    @Published var activityLevel: ActivityLevel {
        didSet {
            UserDefaults.standard.set(activityLevel.rawValue, forKey: "userActivityLevel")
        }
    }
    
    @Published var customCalorieGoal: Double {
        didSet {
            UserDefaults.standard.set(customCalorieGoal, forKey: "customCalorieGoal")
        }
    }
    
    @Published var hasCustomCalorieGoal: Bool {
        didSet {
            UserDefaults.standard.set(hasCustomCalorieGoal, forKey: "hasCustomCalorieGoal")
        }
    }
    
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }
    
    @Published var breakfastTime: (Int, Int) {
        didSet {
            UserDefaults.standard.set(breakfastTime.0, forKey: "breakfastHour")
            UserDefaults.standard.set(breakfastTime.1, forKey: "breakfastMinute")
        }
    }
    
    @Published var lunchTime: (Int, Int) {
        didSet {
            UserDefaults.standard.set(lunchTime.0, forKey: "lunchHour")
            UserDefaults.standard.set(lunchTime.1, forKey: "lunchMinute")
        }
    }
    
    @Published var dinnerTime: (Int, Int) {
        didSet {
            UserDefaults.standard.set(dinnerTime.0, forKey: "dinnerHour")
            UserDefaults.standard.set(dinnerTime.1, forKey: "dinnerMinute")
        }
    }
    
    init() {
        self.age = UserDefaults.standard.object(forKey: "userAge") as? Int ?? 25
        self.gender = Gender(rawValue: UserDefaults.standard.string(forKey: "userGender") ?? "Other") ?? .other
        self.height = UserDefaults.standard.object(forKey: "userHeight") as? Double ?? 170
        self.weight = UserDefaults.standard.object(forKey: "userWeight") as? Double ?? 70
        self.activityLevel = ActivityLevel(rawValue: UserDefaults.standard.string(forKey: "userActivityLevel") ?? "Moderate") ?? .moderate
        self.customCalorieGoal = UserDefaults.standard.object(forKey: "customCalorieGoal") as? Double ?? 0
        self.hasCustomCalorieGoal = UserDefaults.standard.object(forKey: "hasCustomCalorieGoal") as? Bool ?? false
        
        // Notification settings
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.breakfastTime = (
            UserDefaults.standard.object(forKey: "breakfastHour") as? Int ?? 8,
            UserDefaults.standard.object(forKey: "breakfastMinute") as? Int ?? 0
        )
        self.lunchTime = (
            UserDefaults.standard.object(forKey: "lunchHour") as? Int ?? 12,
            UserDefaults.standard.object(forKey: "lunchMinute") as? Int ?? 30
        )
        self.dinnerTime = (
            UserDefaults.standard.object(forKey: "dinnerHour") as? Int ?? 18,
            UserDefaults.standard.object(forKey: "dinnerMinute") as? Int ?? 30
        )
    }
    
    enum Gender: String, CaseIterable, Codable {
        case male = "Male"
        case female = "Female"
        case other = "Other"
        
        var displayName: String { rawValue }
    }
    
    enum ActivityLevel: String, CaseIterable, Codable {
        case sedentary = "Sedentary"
        case light = "Light"
        case moderate = "Moderate"
        case active = "Active"
        case veryActive = "Very Active"
        
        var displayName: String { rawValue }
        var multiplier: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .active: return 1.725
            case .veryActive: return 1.9
            }
        }
    }
    
    // Calculate BMR using Mifflin-St Jeor Equation
    var basalMetabolicRate: Double {
        let bmr: Double
        switch gender {
        case .male:
            bmr = 10 * weight + 6.25 * height - 5 * Double(age) + 5
        case .female:
            bmr = 10 * weight + 6.25 * height - 5 * Double(age) - 161
        case .other:
            // Use average of male and female formulas
            let maleBMR = 10 * weight + 6.25 * height - 5 * Double(age) + 5
            let femaleBMR = 10 * weight + 6.25 * height - 5 * Double(age) - 161
            bmr = (maleBMR + femaleBMR) / 2
        }
        return bmr
    }
    
    // Calculate daily calorie needs
    var recommendedDailyCalories: Double {
        // If height/weight are at default values, use simplified calculation
        // Default height is 170cm, default weight is 70kg
        if height == 170 && weight == 70 {
            // Use simplified calculation based on gender and age only
            return calculateCalorieGoal(gender: gender, age: age)
        }
        return basalMetabolicRate * activityLevel.multiplier
    }
    
    // Get the calorie goal (custom or calculated)
    var dailyCalorieGoal: Double {
        return hasCustomCalorieGoal ? customCalorieGoal : recommendedDailyCalories
    }
    
    // Generate personalized nutrition goals based on user profile (age, gender, calorie goal)
    var nutritionGoals: NutritionGoals {
        let calories = dailyCalorieGoal
        
        // Personalized macronutrient ratios based on age and gender
        let (proteinRatio, carbRatio, fatRatio) = calculateMacronutrientRatios(age: age, gender: gender)
        
        // Calculate grams from ratios (protein and carbs = 4 cal/g, fat = 9 cal/g)
        let protein = calories * proteinRatio / 4
        let carbs = calories * carbRatio / 4
        let fat = calories * fatRatio / 9
        
        return NutritionGoals(
            dailyCalories: calories,
            dailyProtein: protein,
            dailyCarbs: carbs,
            dailyFat: fat
        )
    }
    
    // Calculate personalized macronutrient ratios based on age and gender
    // Returns (protein ratio, carb ratio, fat ratio)
    private func calculateMacronutrientRatios(age: Int, gender: Gender) -> (Double, Double, Double) {
        // Children and adolescents need more protein for growth
        if age < 18 {
            // Ages 0-17: Higher protein for growth, balanced carbs and fat
            if age < 13 {
                // Younger children: 20% protein, 50% carbs, 30% fat
                return (0.20, 0.50, 0.30)
            } else {
                // Adolescents: 25% protein, 45% carbs, 30% fat
                return (0.25, 0.45, 0.30)
            }
        }
        
        // Adults: Gender-specific recommendations
        switch gender {
        case .male:
            // Adult males: Higher protein for muscle maintenance, moderate carbs
            // 25-30% protein, 40-45% carbs, 25-30% fat
            if age < 30 {
                // Younger adults: 30% protein, 40% carbs, 30% fat
                return (0.30, 0.40, 0.30)
            } else if age < 50 {
                // Middle-aged: 25% protein, 45% carbs, 30% fat
                return (0.25, 0.45, 0.30)
            } else {
                // Older adults: Higher protein to prevent muscle loss, moderate carbs
                // 30% protein, 40% carbs, 30% fat
                return (0.30, 0.40, 0.30)
            }
            
        case .female:
            // Adult females: Slightly different needs
            if age < 30 {
                // Younger adults: 25% protein, 45% carbs, 30% fat
                return (0.25, 0.45, 0.30)
            } else if age < 50 {
                // Middle-aged: 25% protein, 45% carbs, 30% fat
                return (0.25, 0.45, 0.30)
            } else {
                // Older adults: Higher protein for muscle preservation
                // 30% protein, 40% carbs, 30% fat
                return (0.30, 0.40, 0.30)
            }
            
        case .other:
            // Use average of male and female recommendations
            if age < 30 {
                return (0.275, 0.425, 0.30) // Average of male and female
            } else if age < 50 {
                return (0.25, 0.45, 0.30)
            } else {
                return (0.30, 0.40, 0.30)
            }
        }
    }
    
    // Calculate calorie goal based on gender and age only (simplified)
    // Based on CDC/Dietary Guidelines reference values and recommendations
    // Handles children, adolescents, and adults with age-appropriate calculations
    func calculateCalorieGoal(gender: Gender, age: Int) -> Double {
        // For children and adolescents, use CDC age-group specific recommendations
        // For adults (18+), use BMR calculation with adult reference values
        
        if age < 18 {
            return calculateCalorieGoalForChildren(gender: gender, age: age)
        } else {
            return calculateCalorieGoalForAdults(gender: gender, age: age)
        }
    }
    
    // Calculate calories for children and adolescents using CDC age-group guidelines
    private func calculateCalorieGoalForChildren(gender: Gender, age: Int) -> Double {
        // CDC recommendations for moderately active children/adolescents
        switch age {
        case 0...1:
            // Ages 0-1: Infants/toddlers
            // Age 0 = first year (0-12 months): ~750 cal average
            // Age 1 = second year (12-24 months): ~950 cal average
            if age == 0 {
                return 750  // First year of life (0-12 months)
            } else {
                return 950  // Second year of life (12-24 months)
            }
            
        case 2...3:
            // Ages 2-3: Both genders ~1,000-1,200 cal (moderately active)
            return 1100
            
        case 4...8:
            // Ages 4-8: Girls 1,200-1,400, Boys 1,200-1,600 (moderately active)
            switch gender {
            case .male: return 1400
            case .female: return 1300
            case .other: return 1350
            }
            
        case 9...13:
            // Ages 9-13: Girls 1,600-2,000, Boys 1,800-2,200 (moderately active)
            switch gender {
            case .male: return 2000
            case .female: return 1800
            case .other: return 1900
            }
            
        case 14...17:
            // Ages 14-17: Girls 1,800-2,400, Boys 2,200-3,200 (moderately active)
            switch gender {
            case .male: return 2700
            case .female: return 2100
            case .other: return 2400
            }
            
        default:
            // Should not reach here, but fallback to adult calculation if somehow age is negative
            return calculateCalorieGoalForAdults(gender: gender, age: 25)
        }
    }
    
    // Calculate calories for adults using BMR with CDC reference values
    private func calculateCalorieGoalForAdults(gender: Gender, age: Int) -> Double {
        // Use CDC reference values: Male (5'10", 154 lbs), Female (5'4", 126 lbs)
        let referenceHeight: Double // in cm
        let referenceWeight: Double // in kg
        
        switch gender {
        case .male:
            referenceHeight = 177.8 // 5'10" (70 inches)
            referenceWeight = 69.9  // 154 lbs
        case .female:
            referenceHeight = 162.6 // 5'4" (64 inches)
            referenceWeight = 57.1  // 126 lbs
        case .other:
            referenceHeight = 170.2 // Average
            referenceWeight = 63.5  // Average
        }
        
        // Calculate BMR using Mifflin-St Jeor Equation
        let bmr: Double
        switch gender {
        case .male:
            bmr = 10 * referenceWeight + 6.25 * referenceHeight - 5 * Double(age) + 5
        case .female:
            bmr = 10 * referenceWeight + 6.25 * referenceHeight - 5 * Double(age) - 161
        case .other:
            let maleBMR = 10 * referenceWeight + 6.25 * referenceHeight - 5 * Double(age) + 5
            let femaleBMR = 10 * referenceWeight + 6.25 * referenceHeight - 5 * Double(age) - 161
            bmr = (maleBMR + femaleBMR) / 2
        }
        
        // Use activity multiplier to match CDC/Dietary Guidelines recommendations
        // CDC moderately active recommendations: Male 25yr ~2,800 cal, Female 25yr ~2,000 cal
        let activityMultiplier: Double
        switch gender {
        case .male:
            activityMultiplier = 1.65 // Results in ~2,790 cal for 25yr male (matches CDC ~2,800)
        case .female:
            activityMultiplier = 1.5  // Results in ~1,950 cal for 25yr female (matches CDC ~2,000)
        case .other:
            activityMultiplier = 1.575 // Average of male and female
        }
        return bmr * activityMultiplier
    }
}
