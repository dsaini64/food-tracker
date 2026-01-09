import Foundation
import SwiftUI
import Combine

// MARK: - Saved Food Model (Template for reusable foods)
struct SavedFood: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let ingredients: [String]?
    let portionSize: String?
    // imageData is NOT stored in UserDefaults - it's stored separately in file system
    // This computed property loads from file system when accessed
    var imageData: Data? {
        get {
            return SavedImageStorage.shared.loadImage(for: id)
        }
        nonmutating set {
            if let data = newValue {
                SavedImageStorage.shared.saveImage(data, for: id)
            } else {
                SavedImageStorage.shared.deleteImage(for: id)
            }
        }
    }
    let isCustom: Bool // true if user-created, false if saved from photo
    
    // Custom Codable implementation to exclude imageData from UserDefaults
    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat, fiber, sugar, sodium
        case ingredients, portionSize, isCustom
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        sodium: Double = 0,
        ingredients: [String]? = nil,
        portionSize: String? = nil,
        imageData: Data? = nil,
        isCustom: Bool = false
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
        self.ingredients = ingredients
        self.portionSize = portionSize
        self.isCustom = isCustom
        
        // Store image data separately in file system (NOT in UserDefaults)
        if let data = imageData {
            SavedImageStorage.shared.saveImage(data, for: id)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Double.self, forKey: .calories)
        protein = try container.decode(Double.self, forKey: .protein)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fat = try container.decode(Double.self, forKey: .fat)
        fiber = try container.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
        sugar = try container.decodeIfPresent(Double.self, forKey: .sugar) ?? 0
        sodium = try container.decodeIfPresent(Double.self, forKey: .sodium) ?? 0
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients)
        portionSize = try container.decodeIfPresent(String.self, forKey: .portionSize)
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(calories, forKey: .calories)
        try container.encode(protein, forKey: .protein)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(fat, forKey: .fat)
        try container.encode(fiber, forKey: .fiber)
        try container.encode(sugar, forKey: .sugar)
        try container.encode(sodium, forKey: .sodium)
        try container.encodeIfPresent(ingredients, forKey: .ingredients)
        try container.encodeIfPresent(portionSize, forKey: .portionSize)
        try container.encode(isCustom, forKey: .isCustom)
        // imageData is NOT encoded - it's stored separately in file system
    }
    
    // Hashable conformance (imageData is excluded since it's computed)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(calories)
        hasher.combine(protein)
        hasher.combine(carbs)
        hasher.combine(fat)
        hasher.combine(fiber)
        hasher.combine(sugar)
        hasher.combine(sodium)
        hasher.combine(isCustom)
    }
    
    static func == (lhs: SavedFood, rhs: SavedFood) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.calories == rhs.calories &&
               lhs.protein == rhs.protein &&
               lhs.carbs == rhs.carbs &&
               lhs.fat == rhs.fat &&
               lhs.fiber == rhs.fiber &&
               lhs.sugar == rhs.sugar &&
               lhs.sodium == rhs.sodium &&
               lhs.isCustom == rhs.isCustom
    }
    
    // Convert to FoodItem for adding to daily log
    func toFoodItem(mealType: FoodItem.MealType) -> FoodItem {
        // Load image data from SavedImageStorage before creating FoodItem
        // This ensures the image is available when FoodItem saves it to ImageStorage
        let loadedImageData = SavedImageStorage.shared.loadImage(for: id)
        
        return FoodItem(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            timestamp: Date(),
            imageData: loadedImageData,
            mealType: mealType,
            ingredients: ingredients,
            location: nil,
            portionSize: portionSize,
            macroGuess: nil
        )
    }
}

// MARK: - Saved Food Manager
class SavedFoodManager: ObservableObject {
    static let shared = SavedFoodManager()
    
    @Published var savedFoods: [SavedFood] = []
    private let savedFoodsKey = "SavedFoods"
    
    private init() {
        loadSavedFoods()
    }
    
    func saveFood(_ food: SavedFood) {
        // Check if food with same name already exists
        if let index = savedFoods.firstIndex(where: { $0.name.lowercased() == food.name.lowercased() }) {
            // Update existing
            savedFoods[index] = food
        } else {
            // Add new
            savedFoods.append(food)
        }
        persistSavedFoods()
    }
    
    func updateFood(_ food: SavedFood, newName: String, newCalories: Double, newProtein: Double, newCarbs: Double, newFat: Double, newFiber: Double, newSugar: Double, newSodium: Double) {
        guard let index = savedFoods.firstIndex(where: { $0.id == food.id }) else {
            print("⚠️ Saved food not found for update")
            return
        }
        
        // Create updated food with same ID and image data
        let updatedFood = SavedFood(
            id: food.id,
            name: newName,
            calories: newCalories,
            protein: newProtein,
            carbs: newCarbs,
            fat: newFat,
            fiber: newFiber,
            sugar: newSugar,
            sodium: newSodium,
            ingredients: food.ingredients,
            portionSize: food.portionSize,
            imageData: food.imageData, // Preserve existing image
            isCustom: food.isCustom
        )
        
        savedFoods[index] = updatedFood
        persistSavedFoods()
        print("✅ Updated saved food: \(updatedFood.name)")
    }
    
    func deleteFood(_ food: SavedFood) {
        savedFoods.removeAll { $0.id == food.id }
        // Delete associated image file
        SavedImageStorage.shared.deleteImage(for: food.id)
        persistSavedFoods()
    }
    
    private func persistSavedFoods() {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(savedFoods)
            UserDefaults.standard.set(encoded, forKey: savedFoodsKey)
        } catch {
            print("❌ Error saving foods: \(error.localizedDescription)")
        }
    }
    
    private func loadSavedFoods() {
        guard let data = UserDefaults.standard.data(forKey: savedFoodsKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            savedFoods = try decoder.decode([SavedFood].self, from: data)
        } catch {
            print("❌ Error loading saved foods: \(error.localizedDescription)")
        }
    }
}

// MARK: - Saved Image Storage (for SavedFood images)
class SavedImageStorage {
    static let shared = SavedImageStorage()
    
    private let fileManager = FileManager.default
    private let imageSaveQueue = DispatchQueue(label: "com.foodtracker.savedimagesave", qos: .utility)
    private var _savedImagesDirectory: URL?
    
    private var savedImagesDirectory: URL {
        if let cached = _savedImagesDirectory {
            return cached
        }
        
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDir = documentsPath.appendingPathComponent("SavedFoodImages", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: imagesDir.path) {
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        
        _savedImagesDirectory = imagesDir
        return imagesDir
    }
    
    private init() {}
    
    func saveImage(_ data: Data, for id: UUID) {
        let dir = savedImagesDirectory
        let fileURL = dir.appendingPathComponent("\(id.uuidString).jpg")
        imageSaveQueue.async {
            try? data.write(to: fileURL)
        }
    }
    
    func loadImage(for id: UUID) -> Data? {
        let fileURL = savedImagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        return try? Data(contentsOf: fileURL)
    }
    
    func deleteImage(for id: UUID) {
        let fileURL = savedImagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        imageSaveQueue.async {
            try? self.fileManager.removeItem(at: fileURL)
        }
    }
    
    func cleanupOldImages(keeping itemIds: Set<UUID>) {
        let dir = savedImagesDirectory
        imageSaveQueue.async {
            guard let files = try? self.fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                return
            }
            
            for fileURL in files {
                let fileName = fileURL.lastPathComponent
                if fileName.hasSuffix(".jpg") {
                    let idString = String(fileName.dropLast(4))
                    if let id = UUID(uuidString: idString), !itemIds.contains(id) {
                        try? self.fileManager.removeItem(at: fileURL)
                    }
                }
            }
        }
    }
}

