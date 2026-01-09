import SwiftUI

struct SavedFoodsView: View {
    @ObservedObject var analysis: NutritionAnalysis
    @ObservedObject private var savedFoodManager = SavedFoodManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFood: SavedFood?
    @State private var showingDeleteAlert = false
    @State private var foodToDelete: SavedFood?
    @State private var foodToEdit: SavedFood?
    @State private var showingEditFood = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom large title aligned with subtext
                Text("Saved Foods")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color(uiColor: .systemGroupedBackground))
                
                List {
                if savedFoodManager.savedFoods.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Saved Foods")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            Text("To save foods here:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                    Text("Go to Today's Foods and tap the + button")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                    Text("Create a custom food")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                    Text("Tap 'Save & Add to Today' or 'Save' to save it")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal)
                } else {
                    Section {
                        Text("Select a food to add it to today's log, edit it, or delete it")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)
                    
                    ForEach(savedFoodManager.savedFoods) { food in
                        SavedFoodRow(
                            food: food,
                            onTap: {
                                selectedFood = food
                            },
                            onEdit: {
                                foodToEdit = food
                                showingEditFood = true
                            },
                            onDelete: {
                                foodToDelete = food
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack {
                        Spacer()
                    }
                }
            }
            .sheet(item: $selectedFood) { food in
                MealTypePickerForSavedFoodView(
                    food: food,
                    onSelect: { mealType in
                        // Create the food item from saved food
                        print("🔄 Converting saved food '\(food.name)' to FoodItem with meal type: \(mealType.rawValue)")
                        let foodItem = food.toFoodItem(mealType: mealType)
                        print("✅ Created FoodItem: \(foodItem.name), timestamp: \(foodItem.timestamp)")
                        
                        // Add to daily log
                        print("📝 Adding food item to daily log...")
                        analysis.dailyLog.addFoodItem(foodItem)
                        
                        // Small delay to ensure state updates before dismissing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            selectedFood = nil
                            dismiss()
                        }
                    },
                    onEdit: {
                        // Set the food to edit and show edit sheet
                        foodToEdit = food
                        selectedFood = nil // Dismiss the meal type picker
                        showingEditFood = true
                    },
                    onDelete: {
                        // Set the food to delete and show delete alert
                        foodToDelete = food
                        selectedFood = nil // Dismiss the meal type picker
                        showingDeleteAlert = true
                    }
                )
            }
            .sheet(item: $foodToEdit) { food in
                EditSavedFoodView(
                    food: food,
                    analysis: analysis,
                    onSave: {
                        foodToEdit = nil
                    }
                )
            }
            .alert("Delete Saved Food", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let food = foodToDelete {
                        savedFoodManager.deleteFood(food)
                    }
                }
            } message: {
                if let food = foodToDelete {
                    Text("Are you sure you want to delete '\(food.name)' from your saved foods?")
                }
            }
        }
    }
}

struct SavedFoodRow: View {
    let food: SavedFood
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Food image or placeholder
                if let imageData = food.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: food.isCustom ? "plus.circle.fill" : "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(food.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if food.isCustom {
                            Text("Custom")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("\(Int(food.calories)) cal • \(Int(food.protein))g protein • \(Int(food.carbs))g carbs • \(Int(food.fat))g fat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

struct MealTypePickerForSavedFoodView: View {
    let food: SavedFood
    let onSelect: (FoodItem.MealType) -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    init(food: SavedFood, onSelect: @escaping (FoodItem.MealType) -> Void, onEdit: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.food = food
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    // Show food info at the top
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .font(.headline)
                            Text("\(Int(food.calories)) cal • \(Int(food.protein))g protein • \(Int(food.carbs))g carbs • \(Int(food.fat))g fat")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    ForEach(FoodItem.MealType.allCases, id: \.self) { mealType in
                        Button(action: {
                            onSelect(mealType)
                            dismiss()
                        }) {
                            HStack {
                                Text(mealType.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Select Meal Type to Add Item to Today")
                }
                
                // Edit Food Section
                if let onEdit = onEdit {
                    Section {
                        Button(action: {
                            onEdit()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                                Text("Edit Food Details")
                                    .foregroundColor(.blue)
                            }
                        }
                    } footer: {
                        Text("Edit the name and nutrition information for this saved food")
                    }
                }
                
                // Delete Food Section
                if let onDelete = onDelete {
                    Section {
                        Button(action: {
                            onDelete()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Delete from Saved Foods")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EditSavedFoodView: View {
    let food: SavedFood
    let analysis: NutritionAnalysis
    let onSave: () -> Void
    @ObservedObject private var savedFoodManager = SavedFoodManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var sugar: String
    @State private var sodium: String
    @State private var resolvedFood: SavedFood?
    
    @StateObject private var foodAnalysisService = FoodAnalysisService()
    @State private var showingAIEstimateAlert = false
    @State private var aiEstimateFoodName: String = ""
    @State private var isEstimating = false
    @State private var estimationError: String?
    @State private var originalName: String
    
    // Computed property to get the current food
    private var currentFood: SavedFood {
        resolvedFood ?? food
    }
    
    init(food: SavedFood, analysis: NutritionAnalysis, onSave: @escaping () -> Void) {
        self.food = food
        self.analysis = analysis
        self.onSave = onSave
        
        // Initialize resolvedFood immediately
        _resolvedFood = State(initialValue: food)
        
        // Initialize state with current values
        _name = State(initialValue: food.name)
        _calories = State(initialValue: String(format: "%.0f", food.calories))
        _protein = State(initialValue: String(format: "%.1f", food.protein))
        _carbs = State(initialValue: String(format: "%.1f", food.carbs))
        _fat = State(initialValue: String(format: "%.1f", food.fat))
        _fiber = State(initialValue: String(format: "%.1f", food.fiber))
        _sugar = State(initialValue: String(format: "%.1f", food.sugar))
        _sodium = State(initialValue: String(format: "%.1f", food.sodium))
        _originalName = State(initialValue: food.name)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Food Name")) {
                    TextField("Food Name", text: $name)
                    
                    // Always show AI estimate button
                    Button(action: {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        if !trimmedName.isEmpty {
                            Task {
                                await estimateMacrosDirectly(foodName: trimmedName)
                            }
                        } else {
                            showingAIEstimateAlert = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.blue)
                            Text("Use AI to Estimate Macros")
                                .foregroundColor(.blue)
                            Spacer()
                            if isEstimating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isEstimating)
                }
                
                Section(header: Text("Nutrition Information")) {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("Calories", text: $calories)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("cal")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("Protein", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("Carbs", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("Fat", text: $fat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Fiber")
                        Spacer()
                        TextField("Fiber", text: $fiber)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sugar")
                        Spacer()
                        TextField("Sugar", text: $sugar)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sodium")
                        Spacer()
                        TextField("Sodium", text: $sodium)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("mg")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Saved Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAIEstimateAlert) {
                AIEstimateSheet(
                    foodName: $aiEstimateFoodName,
                    isEstimating: $isEstimating,
                    onEstimate: {
                        Task {
                            await estimateMacros()
                        }
                    },
                    onCancel: {
                        aiEstimateFoodName = ""
                        showingAIEstimateAlert = false
                    }
                )
            }
            .alert("Estimation Error", isPresented: .constant(estimationError != nil)) {
                Button("OK") {
                    estimationError = nil
                }
            } message: {
                if let error = estimationError {
                    Text(error)
                }
            }
            .onAppear {
                // Ensure food is captured when view appears (fallback if initializer didn't work)
                if resolvedFood == nil {
                    resolvedFood = food
                } else if resolvedFood?.id != food.id {
                    // Update if we have a different food
                    resolvedFood = food
                    // Update the form fields
                    name = food.name
                    calories = String(format: "%.0f", food.calories)
                    protein = String(format: "%.1f", food.protein)
                    carbs = String(format: "%.1f", food.carbs)
                    fat = String(format: "%.1f", food.fat)
                    fiber = String(format: "%.1f", food.fiber)
                    sugar = String(format: "%.1f", food.sugar)
                    sodium = String(format: "%.1f", food.sodium)
                    originalName = food.name
                }
            }
        }
    }
    
    private func estimateMacrosDirectly(foodName: String) async {
        // Check if name hasn't changed and food came from photo analysis (has imageData)
        let nameHasChanged = name.trimmingCharacters(in: .whitespaces) != originalName.trimmingCharacters(in: .whitespaces)
        let hasImageData = food.imageData != nil
        
        // If name hasn't changed AND food came from photo analysis, don't override macros
        if !nameHasChanged && hasImageData {
            await MainActor.run {
                isEstimating = false
            }
            return
        }
        
        await MainActor.run {
            isEstimating = true
            estimationError = nil
        }
        
        do {
            let estimate = try await foodAnalysisService.estimateMacros(foodName: foodName)
            
            await MainActor.run {
                // Populate form fields with estimated values
                self.name = estimate.name
                calories = String(format: "%.0f", estimate.calories)
                protein = String(format: "%.1f", estimate.protein)
                carbs = String(format: "%.1f", estimate.carbs)
                fat = String(format: "%.1f", estimate.fat)
                fiber = String(format: "%.1f", estimate.fiber)
                sugar = String(format: "%.1f", estimate.sugar)
                sodium = String(format: "%.0f", estimate.sodium)
                
                isEstimating = false
            }
        } catch {
            await MainActor.run {
                isEstimating = false
                estimationError = error.localizedDescription
            }
        }
    }
    
    private func estimateMacros() async {
        let foodNameToEstimate = aiEstimateFoodName.trimmingCharacters(in: .whitespaces)
        guard !foodNameToEstimate.isEmpty else {
            return
        }
        
        await MainActor.run {
            isEstimating = true
            estimationError = nil
        }
        
        do {
            let estimate = try await foodAnalysisService.estimateMacros(foodName: foodNameToEstimate)
            
            await MainActor.run {
                // Populate form fields with estimated values
                name = estimate.name
                calories = String(format: "%.0f", estimate.calories)
                protein = String(format: "%.1f", estimate.protein)
                carbs = String(format: "%.1f", estimate.carbs)
                fat = String(format: "%.1f", estimate.fat)
                fiber = String(format: "%.1f", estimate.fiber)
                sugar = String(format: "%.1f", estimate.sugar)
                sodium = String(format: "%.0f", estimate.sodium)
                
                aiEstimateFoodName = ""
                isEstimating = false
                showingAIEstimateAlert = false
            }
        } catch {
            await MainActor.run {
                isEstimating = false
                estimationError = error.localizedDescription
            }
        }
    }
    
    private func saveChanges() {
        // Use currentFood to ensure we have the latest reference
        let foodToUpdate = currentFood
        
        // Parse values with defaults
        let caloriesValue = Double(calories) ?? foodToUpdate.calories
        let proteinValue = Double(protein) ?? foodToUpdate.protein
        let carbsValue = Double(carbs) ?? foodToUpdate.carbs
        let fatValue = Double(fat) ?? foodToUpdate.fat
        let fiberValue = Double(fiber) ?? foodToUpdate.fiber
        let sugarValue = Double(sugar) ?? foodToUpdate.sugar
        let sodiumValue = Double(sodium) ?? foodToUpdate.sodium
        
        // Validate that name is not empty
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }
        
        // Update the saved food
        savedFoodManager.updateFood(
            foodToUpdate,
            newName: trimmedName,
            newCalories: max(0, caloriesValue),
            newProtein: max(0, proteinValue),
            newCarbs: max(0, carbsValue),
            newFat: max(0, fatValue),
            newFiber: max(0, fiberValue),
            newSugar: max(0, sugarValue),
            newSodium: max(0, sodiumValue)
        )
        
        // Update all FoodItem instances in today's log that match this saved food
        // Match by original name (before edit) to find all instances that came from this saved food
        let trimmedOriginalName = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingItems = analysis.dailyLog.todayFoodItems.filter { item in
            item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedOriginalName.lowercased()
        }
        
        // Update each matching FoodItem with the new values
        for item in matchingItems {
            analysis.dailyLog.updateFoodItem(
                item,
                name: trimmedName,
                calories: max(0, caloriesValue),
                protein: max(0, proteinValue),
                carbs: max(0, carbsValue),
                fat: max(0, fatValue),
                fiber: max(0, fiberValue),
                sugar: max(0, sugarValue),
                sodium: max(0, sodiumValue)
            )
        }
        
        if !matchingItems.isEmpty {
            print("✅ Updated \(matchingItems.count) FoodItem instance(s) in today's log to match edited saved food")
        }
        
        onSave()
        dismiss()
    }
}

#Preview {
    SavedFoodsView(analysis: NutritionAnalysis(dailyLog: DailyFoodLog()))
}

