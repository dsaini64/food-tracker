import Foundation
import HealthKit
import Combine

/// Manages integration with Apple HealthKit for nutrition data
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "healthKitEnabled")
            if isEnabled && !isAuthorized {
                requestAuthorization()
            }
        }
    }
    
    private let healthStore = HKHealthStore()
    
    // Nutrition data types we want to read/write
    private let typesToWrite: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!,
        HKQuantityType.quantityType(forIdentifier: .dietarySugar)!,
        HKQuantityType.quantityType(forIdentifier: .dietarySodium)!
    ]
    
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
    ]
    
    private init() {
        // Load saved preference
        self.isEnabled = UserDefaults.standard.bool(forKey: "healthKitEnabled")
        
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit is not available on this device")
            return
        }
        
        // Check authorization status
        checkAuthorizationStatus()
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            authorizationStatus = .notDetermined
            return
        }
        
        let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        authorizationStatus = healthStore.authorizationStatus(for: energyType)
        isAuthorized = authorizationStatus == .sharingAuthorized
    }
    
    /// Request HealthKit authorization
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit is not available on this device")
            return
        }
        
        print("🔐 Requesting HealthKit authorization...")
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ HealthKit authorization error: \(error.localizedDescription)")
                    self?.isAuthorized = false
                    return
                }
                
                if success {
                    print("✅ HealthKit authorization granted")
                    self?.checkAuthorizationStatus()
                } else {
                    print("⚠️ HealthKit authorization denied")
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    /// Write nutrition data for a food item to HealthKit
    func saveFoodItem(_ item: FoodItem) {
        guard isEnabled && isAuthorized else {
            print("⚠️ HealthKit sync is disabled or not authorized")
            return
        }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit is not available")
            return
        }
        
        print("💾 Saving food item to HealthKit: \(item.name)")
        
        // Create samples for each nutrition value
        var samples: [HKQuantitySample] = []
        
        // Dietary Energy (Calories) - in kilocalories
        if item.calories > 0 {
            let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
            let energyQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: item.calories)
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: energyQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(energySample)
        }
        
        // Protein - in grams
        if item.protein > 0 {
            let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!
            let proteinQuantity = HKQuantity(unit: HKUnit.gram(), doubleValue: item.protein)
            let proteinSample = HKQuantitySample(
                type: proteinType,
                quantity: proteinQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(proteinSample)
        }
        
        // Carbohydrates - in grams
        if item.carbs > 0 {
            let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
            let carbsQuantity = HKQuantity(unit: HKUnit.gram(), doubleValue: item.carbs)
            let carbsSample = HKQuantitySample(
                type: carbsType,
                quantity: carbsQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(carbsSample)
        }
        
        // Total Fat - in grams
        if item.fat > 0 {
            let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
            let fatQuantity = HKQuantity(unit: HKUnit.gram(), doubleValue: item.fat)
            let fatSample = HKQuantitySample(
                type: fatType,
                quantity: fatQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(fatSample)
        }
        
        // Fiber - in grams
        if item.fiber > 0 {
            let fiberType = HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!
            let fiberQuantity = HKQuantity(unit: HKUnit.gram(), doubleValue: item.fiber)
            let fiberSample = HKQuantitySample(
                type: fiberType,
                quantity: fiberQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(fiberSample)
        }
        
        // Sugar - in grams
        if item.sugar > 0 {
            let sugarType = HKQuantityType.quantityType(forIdentifier: .dietarySugar)!
            let sugarQuantity = HKQuantity(unit: HKUnit.gram(), doubleValue: item.sugar)
            let sugarSample = HKQuantitySample(
                type: sugarType,
                quantity: sugarQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(sugarSample)
        }
        
        // Sodium - in milligrams
        if item.sodium > 0 {
            let sodiumType = HKQuantityType.quantityType(forIdentifier: .dietarySodium)!
            let sodiumQuantity = HKQuantity(unit: HKUnit.gramUnit(with: .milli), doubleValue: item.sodium)
            let sodiumSample = HKQuantitySample(
                type: sodiumType,
                quantity: sodiumQuantity,
                start: item.timestamp,
                end: item.timestamp,
                metadata: [
                    HKMetadataKeyFoodType: item.name,
                    "mealType": item.mealType.rawValue
                ]
            )
            samples.append(sodiumSample)
        }
        
        // Save all samples
        guard !samples.isEmpty else {
            print("⚠️ No nutrition data to save for \(item.name)")
            return
        }
        
        healthStore.save(samples) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error saving to HealthKit: \(error.localizedDescription)")
                } else if success {
                    print("✅ Successfully saved \(samples.count) nutrition samples to HealthKit")
                }
            }
        }
    }
    
    /// Delete nutrition data for a food item from HealthKit
    /// Note: HealthKit doesn't support direct deletion by metadata, so we'll delete samples for the timestamp range
    func deleteFoodItem(_ item: FoodItem) {
        guard isEnabled && isAuthorized else {
            return
        }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        
        print("🗑️ Deleting food item from HealthKit: \(item.name)")
        
        // HealthKit doesn't have a direct way to delete by metadata
        // We'll query for samples at the same timestamp and delete them
        let startDate = item.timestamp.addingTimeInterval(-60) // 1 minute before
        let endDate = item.timestamp.addingTimeInterval(60) // 1 minute after
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        // Delete each nutrition type
        for type in typesToWrite {
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [weak self] query, samples, error in
                guard let samples = samples as? [HKQuantitySample] else { return }
                
                // Filter samples that match our food item name
                let matchingSamples = samples.filter { sample in
                    sample.metadata?[HKMetadataKeyFoodType] as? String == item.name
                }
                
                if !matchingSamples.isEmpty {
                    self?.healthStore.delete(matchingSamples) { success, error in
                        if let error = error {
                            print("❌ Error deleting from HealthKit: \(error.localizedDescription)")
                        } else if success {
                            print("✅ Deleted \(matchingSamples.count) samples from HealthKit")
                        }
                    }
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Read today's nutrition data from HealthKit
    func readTodayNutrition(completion: @escaping (Double, Double, Double, Double) -> Void) {
        guard isEnabled && isAuthorized else {
            completion(0, 0, 0, 0)
            return
        }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(0, 0, 0, 0)
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )
        
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        
        let group = DispatchGroup()
        
        // Read calories
        group.enter()
        let caloriesType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let caloriesQuery = HKStatisticsQuery(
            quantityType: caloriesType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let sum = result?.sumQuantity() {
                calories = sum.doubleValue(for: HKUnit.kilocalorie())
            }
            group.leave()
        }
        healthStore.execute(caloriesQuery)
        
        // Read protein
        group.enter()
        let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!
        let proteinQuery = HKStatisticsQuery(
            quantityType: proteinType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let sum = result?.sumQuantity() {
                protein = sum.doubleValue(for: HKUnit.gram())
            }
            group.leave()
        }
        healthStore.execute(proteinQuery)
        
        // Read carbs
        group.enter()
        let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
        let carbsQuery = HKStatisticsQuery(
            quantityType: carbsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let sum = result?.sumQuantity() {
                carbs = sum.doubleValue(for: HKUnit.gram())
            }
            group.leave()
        }
        healthStore.execute(carbsQuery)
        
        // Read fat
        group.enter()
        let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
        let fatQuery = HKStatisticsQuery(
            quantityType: fatType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let sum = result?.sumQuantity() {
                fat = sum.doubleValue(for: HKUnit.gram())
            }
            group.leave()
        }
        healthStore.execute(fatQuery)
        
        group.notify(queue: .main) {
            completion(calories, protein, carbs, fat)
        }
    }
}
