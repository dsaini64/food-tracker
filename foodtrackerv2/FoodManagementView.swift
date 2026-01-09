import SwiftUI

struct FoodManagementView: View {
    @ObservedObject var analysis: NutritionAnalysis
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: FoodItem?
    @State private var itemToEdit: FoodItem?
    @State private var itemToEditMealType: FoodItem.MealType?
    @State private var showingCustomFoodCreator = false
    @State private var showingEditFoodItem = false
    @State private var itemToEditDetails: FoodItem?
    @State private var showingSavedFoods = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(analysis.dailyLog.todayFoodItems) { item in
                    FoodItemRow(
                        item: item,
                        onMealTypeTap: {
                            // Capture the item data - use the item directly from the ForEach
                            // This ensures we always have a valid reference
                            let capturedItem = analysis.dailyLog.todayFoodItems.first(where: { $0.id == item.id }) ?? item
                            itemToEdit = capturedItem
                            itemToEditMealType = capturedItem.mealType
                            // Sheet will automatically show when itemToEdit is set (using .sheet(item:) modifier)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            itemToDelete = item
                            showingDeleteAlert = true
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            itemToEditDetails = item
                            showingEditFoodItem = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                
            }
            .navigationTitle("Today's Foods")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSavedFoods = true
                    }) {
                        Text("Saved Foods")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCustomFoodCreator = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Delete Food Item", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        analysis.dailyLog.removeFoodItem(item)
                    }
                }
            } message: {
                if let item = itemToDelete {
                    Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
                }
            }
            .sheet(item: $itemToEdit) { item in
                // Use captured meal type, or fall back to the item's current meal type
                let currentMealType: FoodItem.MealType = itemToEditMealType ?? item.mealType
                
                    MealTypePickerView(
                    currentMealType: currentMealType,
                    foodItem: item,
                    analysis: analysis,
                        onSelect: { newMealType in
                        // Find the item by ID to ensure we're updating the correct one
                        if let itemToUpdate = analysis.dailyLog.todayFoodItems.first(where: { $0.id == item.id }) {
                            analysis.dailyLog.updateFoodItemMealType(itemToUpdate, to: newMealType)
                        } else {
                            // Fallback: use the item directly
                            analysis.dailyLog.updateFoodItemMealType(item, to: newMealType)
                        }
                            itemToEdit = nil
                        itemToEditMealType = nil
                    }
                )
                .onDisappear {
                    // Clear state when sheet is dismissed (e.g., by swiping down)
                    itemToEditMealType = nil
                }
            }
            .sheet(isPresented: $showingCustomFoodCreator) {
                CustomFoodCreatorView(analysis: analysis)
            }
            .sheet(isPresented: $showingSavedFoods) {
                SavedFoodsView(analysis: analysis)
            }
            .sheet(isPresented: $showingEditFoodItem) {
                if let item = itemToEditDetails {
                    EditFoodItemView(
                        foodItem: item,
                        analysis: analysis,
                        onSave: {
                            showingEditFoodItem = false
                            itemToEditDetails = nil
                        }
                    )
                }
            }
        }
    }
}

struct FoodItemRow: View {
    let item: FoodItem
    let onMealTypeTap: () -> Void
    
    var body: some View {
        Button(action: onMealTypeTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(Int(item.calories)) cal • \(Int(item.protein))g protein • \(Int(item.carbs))g carbs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(item.categorizedMealType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DateFormatter.timeFormatter.string(from: item.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MealTypePickerView: View {
    let currentMealType: FoodItem.MealType
    let foodItem: FoodItem
    let analysis: NutritionAnalysis
    let onSelect: (FoodItem.MealType) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var savedFoodManager = SavedFoodManager.shared
    @State private var showingSaveConfirmation = false
    @State private var showingEditFoodItem = false
    @State private var showingDeleteAlert = false
    @State private var showingTimePicker = false
    @State private var selectedTimestamp: Date
    
    // Initialize resolvedFoodItem immediately with the tapped food item
    @State private var resolvedFoodItem: FoodItem?
    
    // Computed property to get the current food item (always non-optional)
    private var currentFoodItem: FoodItem {
        // Prefer the latest version from the log if available, otherwise fall back to the passed-in item
        if let resolved = resolvedFoodItem {
            return resolved
        }
        if let latest = analysis.dailyLog.foodItems.first(where: { $0.id == foodItem.id }) {
            return latest
        }
        return foodItem
    }
    
    // Custom initializer to set resolvedFoodItem immediately
    init(currentMealType: FoodItem.MealType, foodItem: FoodItem, analysis: NutritionAnalysis, onSelect: @escaping (FoodItem.MealType) -> Void) {
        self.currentMealType = currentMealType
        self.foodItem = foodItem
        self.analysis = analysis
        self.onSelect = onSelect
        // Initialize resolvedFoodItem with the provided foodItem.
        _resolvedFoodItem = State(initialValue: foodItem)
        // Initialize selectedTimestamp with the food item's timestamp
        _selectedTimestamp = State(initialValue: foodItem.timestamp)
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Change Meal Type")) {
                    ForEach(FoodItem.MealType.allCases, id: \.self) { mealType in
                        Button(action: {
                            onSelect(mealType)
                            dismiss()
                        }) {
                            HStack {
                                Text(mealType.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if mealType == currentMealType {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Time Logged")) {
                    Button(action: {
                        withAnimation {
                            showingTimePicker.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("Time")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(DateFormatter.timeFormatter.string(from: selectedTimestamp))
                                .foregroundColor(.secondary)
                            Image(systemName: showingTimePicker ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    if showingTimePicker {
                        DatePicker(
                            "Time",
                            selection: $selectedTimestamp,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .onChange(of: selectedTimestamp) { newTimestamp in
                            // Update the timestamp when user changes it
                            let item = currentFoodItem
                            analysis.dailyLog.updateFoodItemTimestamp(item, to: newTimestamp)
                            // Update resolvedFoodItem to reflect the change
                            if let updatedItem = analysis.dailyLog.foodItems.first(where: { $0.id == item.id }) {
                                resolvedFoodItem = updatedItem
                            }
                        }
                    }
                }
                
                // Actions Section - use currentFoodItem computed property
                let item = currentFoodItem
                Section {
                    Button(action: {
                        showingEditFoodItem = true
                    }) {
                        HStack {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                            Text("Edit Food Details")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Button(action: {
                        saveFoodItem(item)
                        showingSaveConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.blue)
                            Text("Save Food for Later")
                                .foregroundColor(.blue)
                        }
                    }
                } footer: {
                    let item = currentFoodItem
                    Text(item.imageData == nil 
                         ? "Save this food to quickly add it again later without reentering details"
                         : "Save this food to quickly add it again later without taking another photo")
                }
                
                Section {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete from Today's Log")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Ensure we capture the latest version of this specific food item when the view appears.
                if let latest = analysis.dailyLog.foodItems.first(where: { $0.id == foodItem.id }) {
                    resolvedFoodItem = latest
                    selectedTimestamp = latest.timestamp
                } else {
                    resolvedFoodItem = foodItem
                    selectedTimestamp = foodItem.timestamp
                }
            }
            .alert("Food Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                let item = currentFoodItem
                Text("'\(item.name)' has been saved. You can find it in Saved Foods.")
            }
            .alert("Delete Food Item", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    let item = currentFoodItem
                    analysis.dailyLog.removeFoodItem(item)
                    dismiss()
                }
            } message: {
                let item = currentFoodItem
                Text("Are you sure you want to delete '\(item.name)' from today's food log? This action cannot be undone.")
            }
            .sheet(isPresented: $showingEditFoodItem) {
                let item = currentFoodItem
                EditFoodItemView(
                    foodItem: item,
                    analysis: analysis,
                    onSave: {
                        // Refresh resolvedFoodItem after edit
                        if let updatedItem = analysis.dailyLog.todayFoodItems.first(where: { $0.id == item.id }) {
                            resolvedFoodItem = updatedItem
                        }
                    }
                )
            }
        }
    }
    
    private func saveFoodItem(_ item: FoodItem) {
        let imageData = item.imageData
        let savedFood = SavedFood(
            name: item.name,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            fiber: item.fiber,
            sugar: item.sugar,
            sodium: item.sodium,
            ingredients: item.ingredients,
            portionSize: item.portionSize,
            imageData: imageData,
            isCustom: false
        )
        savedFoodManager.saveFood(savedFood)
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    FoodManagementView(analysis: NutritionAnalysis(dailyLog: DailyFoodLog()))
}

#Preview("Meal Type Picker") {
    MealTypePickerView(
        currentMealType: .lunch,
        foodItem: FoodItem(
            name: "Sample Food",
            calories: 100,
            protein: 5,
            carbs: 10,
            fat: 3,
            fiber: 2,
            sugar: 1,
            sodium: 50,
            timestamp: Date(),
            imageData: nil,
            mealType: .lunch
        ),
        analysis: NutritionAnalysis(dailyLog: DailyFoodLog()),
        onSelect: { _ in }
    )
}

// MARK: - Edit Food Item View
struct EditFoodItemView: View {
    let foodItem: FoodItem
    @ObservedObject var analysis: NutritionAnalysis
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var sugar: String
    @State private var sodium: String
    @State private var resolvedFoodItem: FoodItem?
    
    @StateObject private var foodAnalysisService = FoodAnalysisService()
    @State private var showingAIEstimateAlert = false
    @State private var aiEstimateFoodName: String = ""
    @State private var isEstimating = false
    @State private var estimationError: String?
    @State private var originalName: String
    
    init(foodItem: FoodItem, analysis: NutritionAnalysis, onSave: @escaping () -> Void) {
        self.foodItem = foodItem
        self.analysis = analysis
        self.onSave = onSave
        
        // Initialize state with current values
        _name = State(initialValue: foodItem.name)
        _calories = State(initialValue: String(format: "%.0f", foodItem.calories))
        _protein = State(initialValue: String(format: "%.1f", foodItem.protein))
        _carbs = State(initialValue: String(format: "%.1f", foodItem.carbs))
        _fat = State(initialValue: String(format: "%.1f", foodItem.fat))
        _fiber = State(initialValue: String(format: "%.1f", foodItem.fiber))
        _sugar = State(initialValue: String(format: "%.1f", foodItem.sugar))
        _sodium = State(initialValue: String(format: "%.1f", foodItem.sodium))
        _originalName = State(initialValue: foodItem.name)
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
            .navigationTitle("Edit Food")
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
                // Ensure foodItem is captured when view appears
                if resolvedFoodItem == nil {
                    // Look up the current item from the daily log to ensure we have the latest version
                    if let currentItem = analysis.dailyLog.todayFoodItems.first(where: { $0.id == foodItem.id }) {
                        resolvedFoodItem = currentItem
                    } else {
                        resolvedFoodItem = foodItem
                    }
                }
            }
        }
    }
    
    private func estimateMacrosDirectly(foodName: String) async {
        // Check if name hasn't changed and food came from photo analysis (has imageData)
        let nameHasChanged = name.trimmingCharacters(in: .whitespaces) != originalName.trimmingCharacters(in: .whitespaces)
        let hasImageData = foodItem.imageData != nil
        
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
        // Get the current item from the daily log
        let currentItem = resolvedFoodItem ?? analysis.dailyLog.todayFoodItems.first(where: { $0.id == foodItem.id }) ?? foodItem
        
        // Parse values with defaults
        let caloriesValue = Double(calories) ?? currentItem.calories
        let proteinValue = Double(protein) ?? currentItem.protein
        let carbsValue = Double(carbs) ?? currentItem.carbs
        let fatValue = Double(fat) ?? currentItem.fat
        let fiberValue = Double(fiber) ?? currentItem.fiber
        let sugarValue = Double(sugar) ?? currentItem.sugar
        let sodiumValue = Double(sodium) ?? currentItem.sodium
        
        // Update the food item
        analysis.dailyLog.updateFoodItem(
            currentItem,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? currentItem.name : name.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: max(0, caloriesValue),
            protein: max(0, proteinValue),
            carbs: max(0, carbsValue),
            fat: max(0, fatValue),
            fiber: max(0, fiberValue),
            sugar: max(0, sugarValue),
            sodium: max(0, sodiumValue)
        )
        
        onSave()
        dismiss()
    }
}
