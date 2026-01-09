import SwiftUI

struct CustomFoodCreatorView: View {
    @ObservedObject var analysis: NutritionAnalysis
    @ObservedObject private var savedFoodManager = SavedFoodManager.shared
    @Environment(\.dismiss) private var dismiss
    
    let fromSavedFoods: Bool
    
    @StateObject private var foodAnalysisService = FoodAnalysisService()
    
    init(analysis: NutritionAnalysis, fromSavedFoods: Bool = false) {
        self.analysis = analysis
        self.fromSavedFoods = fromSavedFoods
    }
    
    @State private var foodName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var fiber: String = ""
    @State private var sugar: String = ""
    @State private var sodium: String = ""
    
    @State private var showingMealTypePicker = false
    @State private var showingSaveConfirmation = false
    @State private var pendingMealTypeSelection = false
    @State private var showingAIEstimateAlert = false
    @State private var aiEstimateFoodName: String = ""
    @State private var isEstimating = false
    @State private var estimationError: String?
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, calories, protein, carbs, fat, fiber, sugar, sodium
    }
    
    private var isValid: Bool {
        !foodName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !calories.isEmpty &&
        Double(calories) != nil &&
        Double(calories) ?? 0 >= 0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Food Information")) {
                    TextField("Food Name", text: $foodName)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .calories
                        }
                    
                    Button(action: {
                        let trimmedName = foodName.trimmingCharacters(in: .whitespaces)
                        if !trimmedName.isEmpty {
                            // Food name is already entered, estimate directly
                            Task {
                                await estimateMacrosDirectly(foodName: trimmedName)
                            }
                        } else {
                            // Food name is blank, show sheet to enter name
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
                
                Section(header: Text("Nutrition (per serving)")) {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .calories)
                            .frame(width: 100)
                        Text("cal")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .protein)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .carbs)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .fat)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Optional Details")) {
                    HStack {
                        Text("Fiber")
                        Spacer()
                        TextField("0", text: $fiber)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .fiber)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sugar")
                        Spacer()
                        TextField("0", text: $sugar)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .sugar)
                            .frame(width: 100)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sodium")
                        Spacer()
                        TextField("0", text: $sodium)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .sodium)
                            .frame(width: 100)
                        Text("mg")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    if fromSavedFoods {
                        // Options when accessed from Saved Foods screen
                        Button(action: {
                            saveAndAdd()
                        }) {
                            HStack {
                                Spacer()
                                Text("Save & Add to Today")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!isValid)
                        
                        Button(action: {
                            saveOnly()
                        }) {
                            HStack {
                                Spacer()
                                Text("Save")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!isValid)
                    } else {
                        // Options when accessed from Today's Foods screen
                        Button(action: {
                            addToToday()
                        }) {
                            HStack {
                                Spacer()
                                Text("Add to Today")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!isValid)
                        
                        Button(action: {
                            saveAndAdd()
                        }) {
                            HStack {
                                Spacer()
                                Text("Save & Add to Today")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!isValid)
                        
                        Button(action: {
                            saveOnly()
                        }) {
                            HStack {
                                Spacer()
                                Text("Save")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!isValid)
                    }
                } footer: {
                    Text("Save this food to quickly add it again later without reentering details")
                }
            }
            .navigationTitle("Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMealTypePicker) {
                // Use the saved food from SavedFoodManager if available, otherwise create from form
                let foodToUse: SavedFood = {
                    let formFood = createSavedFood()
                    // Try to find the saved version by name (in case it was just saved)
                    if let savedFood = savedFoodManager.savedFoods.first(where: { 
                        $0.name.lowercased() == formFood.name.lowercased() 
                    }) {
                        return savedFood
                    }
                    return formFood
                }()
                
                MealTypePickerForSavedFoodView(
                    food: foodToUse,
                    onSelect: { mealType in
                        // Use the same food that was shown in the picker
                        let foodItem = foodToUse.toFoodItem(mealType: mealType)
                        
                        // Add to daily log
                        analysis.dailyLog.addFoodItem(foodItem)
                        
                        // Small delay to ensure state updates before dismissing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingMealTypePicker = false
                            dismiss()
                        }
                    }
                )
            }
            .alert("Food Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) {
                    // After dismissing the alert, show meal type picker if pending
                    if pendingMealTypeSelection {
                        pendingMealTypeSelection = false
                        showingMealTypePicker = true
                    } else {
                        // If just saving (not adding), dismiss the view
                        dismiss()
                    }
                }
            } message: {
                Text("'\(foodName)' has been saved. You can find it in Saved Foods.")
            }
            .sheet(isPresented: $showingAIEstimateAlert, onDismiss: {
                // Dismiss keyboard when sheet is dismissed
                focusedField = nil
            }) {
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
                        // Dismiss keyboard when canceling
                        focusedField = nil
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
                // Focus on name field when view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .name
                }
            }
        }
    }
    
    private func createSavedFood() -> SavedFood {
        return SavedFood(
            name: foodName.trimmingCharacters(in: .whitespaces),
            calories: Double(calories) ?? 0,
            protein: Double(protein) ?? 0,
            carbs: Double(carbs) ?? 0,
            fat: Double(fat) ?? 0,
            fiber: Double(fiber) ?? 0,
            sugar: Double(sugar) ?? 0,
            sodium: Double(sodium) ?? 0,
            ingredients: nil,
            portionSize: nil,
            imageData: nil,
            isCustom: true
        )
    }
    
    private func addToToday() {
        showingMealTypePicker = true
    }
    
    private func saveAndAdd() {
        let savedFood = createSavedFood()
        savedFoodManager.saveFood(savedFood)
        pendingMealTypeSelection = true
        showingSaveConfirmation = true
    }
    
    private func saveOnly() {
        let savedFood = createSavedFood()
        savedFoodManager.saveFood(savedFood)
        showingSaveConfirmation = true
    }
    
    private func estimateMacrosDirectly(foodName: String) async {
        await MainActor.run {
            isEstimating = true
            estimationError = nil
        }
        
        do {
            let estimate = try await foodAnalysisService.estimateMacros(foodName: foodName)
            
            await MainActor.run {
                // Populate form fields with estimated values
                self.foodName = estimate.name
                calories = String(format: "%.0f", estimate.calories)
                protein = String(format: "%.1f", estimate.protein)
                carbs = String(format: "%.1f", estimate.carbs)
                fat = String(format: "%.1f", estimate.fat)
                fiber = String(format: "%.1f", estimate.fiber)
                sugar = String(format: "%.1f", estimate.sugar)
                sodium = String(format: "%.0f", estimate.sodium)
                
                isEstimating = false
                
                // Dismiss keyboard by removing focus
                focusedField = nil
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
                foodName = estimate.name
                calories = String(format: "%.0f", estimate.calories)
                protein = String(format: "%.1f", estimate.protein)
                carbs = String(format: "%.1f", estimate.carbs)
                fat = String(format: "%.1f", estimate.fat)
                fiber = String(format: "%.1f", estimate.fiber)
                sugar = String(format: "%.1f", estimate.sugar)
                sodium = String(format: "%.0f", estimate.sodium)
                
                aiEstimateFoodName = ""
                isEstimating = false
                
                // Dismiss keyboard first, then dismiss sheet
                focusedField = nil
                
                // Small delay to ensure keyboard dismisses before sheet closes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingAIEstimateAlert = false
                }
            }
        } catch {
            await MainActor.run {
                isEstimating = false
                estimationError = error.localizedDescription
                // Keep the sheet open so user can try again
            }
        }
    }
}

// MARK: - AI Estimate Sheet
struct AIEstimateSheet: View {
    @Binding var foodName: String
    @Binding var isEstimating: Bool
    let onEstimate: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    // Helper function to dismiss keyboard
    private func dismissKeyboard() {
        isTextFieldFocused = false
        // Also use UIApplication to ensure keyboard dismisses
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Enter the name of the food item (e.g., 'Chipotle sofritas burrito') and AI will estimate its macros.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Food Name")) {
                    TextField("e.g., Chipotle sofritas burrito", text: $foodName)
                        .textInputAutocapitalization(.words)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !foodName.trimmingCharacters(in: .whitespaces).isEmpty {
                                dismissKeyboard()
                                onEstimate()
                            }
                        }
                }
                
                Section {
                    Button(action: {
                        dismissKeyboard()
                        onEstimate()
                    }) {
                        HStack {
                            Spacer()
                            if isEstimating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "sparkles")
                                Text("Estimate Macros")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(foodName.trimmingCharacters(in: .whitespaces).isEmpty || isEstimating)
                }
            }
            .navigationTitle("AI Macro Estimation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismissKeyboard()
                        onCancel()
                        dismiss()
                    }
                    .disabled(isEstimating)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }
}

#Preview {
    CustomFoodCreatorView(analysis: NutritionAnalysis(dailyLog: DailyFoodLog()))
}

