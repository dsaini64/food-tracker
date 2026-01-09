import SwiftUI

struct SnapchatCameraView: View {
    let analysis: NutritionAnalysis
    @ObservedObject var foodRecognition: FoodRecognitionService
    
    @State private var isCapturing = false
    @State private var showingImagePicker = false
    @State private var capturedImage: UIImage?
    @State private var isFlashOn = false
    @State private var selectedMealType: FoodItem.MealType
    @State private var showingMealPicker = false
    @State private var showingEditFoodItem = false
    @State private var foodItemToEdit: FoodItem?
    
    init(analysis: NutritionAnalysis, foodRecognition: FoodRecognitionService) {
        self.analysis = analysis
        self.foodRecognition = foodRecognition
        // Default to current time-based meal type
        _selectedMealType = State(initialValue: FoodItem.MealType.fromTime())
    }
    
    var body: some View {
        ZStack {
            // Live Camera Feed
            LiveCameraView(
                isCapturing: $isCapturing,
                isFlashOn: $isFlashOn,
                onImageCaptured: { image in
                    print("📱 Image captured, size: \(image.size)")
                    capturedImage = image
                    // Start analysis immediately with selected meal type
                    foodRecognition.selectedMealType = selectedMealType
                    foodRecognition.analyzeFoodImage(image, mealType: selectedMealType)
                }
            )
            .ignoresSafeArea()
            
            // Top Status Bar
            VStack {
                HStack {
                    // Calorie Progress
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(analysis.dailyLog.totalCalories))/\(Int(analysis.goals.dailyCalories)) cal")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        ProgressView(value: analysis.caloriesProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 120)
                    }
                    
                    Spacer()
                    
                    // Quick Actions
                    HStack(spacing: 20) {
                        Button(action: {
                            print("🔦 Flash button tapped! Current state: \(isFlashOn)")
                            isFlashOn.toggle()
                            print("🔦 Flash state changed to: \(isFlashOn)")
                        }) {
                            Image(systemName: isFlashOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title2)
                                .foregroundColor(isFlashOn ? .yellow : .white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(22)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .contentShape(Rectangle()) // Make the entire bar area tappable/draggable
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { _ in }
                        .onEnded { _ in }
                ) // Block swipe gestures on this bar from propagating to parent TabView
                
                Spacer()
            }
            .overlay(
                // Meal Type Selector - Top Right (overlay so it doesn't affect layout)
                VStack {
                    HStack {
                        Spacer()
                        mealTypeSelector
                            .padding(.trailing, 20)
                            .padding(.top, 64) // Position right below flashlight button with more spacing
                    }
                    Spacer()
                }
            )
            
            // Bottom UI
            VStack {
                Spacer()
                
                // Recent Food Items
                if !analysis.dailyLog.todayFoodItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(analysis.dailyLog.todayFoodItems.suffix(5), id: \.id) { item in
                                // Don't show "Processing..." items in the list - they're shown in the progress indicator
                                // Get the latest version of the item to ensure we show updated name
                                let currentItem = analysis.dailyLog.foodItems.first(where: { $0.id == item.id }) ?? item
                                if currentItem.name != "Processing..." {
                                VStack(spacing: 4) {
                                        Text(currentItem.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    
                                    if currentItem.calories > 0 {
                                        Text("\(Int(currentItem.calories)) cal")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 60)
                }
                
                // Analysis Progress Indicator
                if foodRecognition.isAnalyzing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        
                        if !foodRecognition.analysisProgress.isEmpty {
                            Text(foodRecognition.analysisProgress)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        } else {
                            Text("Analyzing...")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.bottom, 20)
                }
                
                // Capture Button
                VStack(spacing: 8) {
                    // Check if any food item is still processing
                    let hasProcessingItem = analysis.dailyLog.todayFoodItems.contains { $0.name == "Processing..." }
                    
                    Button(action: {
                        // Set analyzing state immediately for instant UI feedback
                        foodRecognition.isAnalyzing = true
                        foodRecognition.analysisProgress = "Analyzing..."
                        // Create placeholder immediately when button is pressed
                        foodRecognition.createPlaceholderItem()
                        isCapturing = true
                        // Pass selected meal type to analysis
                        foodRecognition.selectedMealType = selectedMealType
                    }) {
                        ZStack {
                            // Outer ring
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 70, height: 70)
                            
                            // Inner circle
                            Circle()
                                .fill(Color.white)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .disabled(foodRecognition.isAnalyzing || hasProcessingItem)
                    .opacity((foodRecognition.isAnalyzing || hasProcessingItem) ? 0.5 : 1.0)
                }
                .padding(.bottom, 30)
            }
            
            // Analysis Results Overlay
            if let result = foodRecognition.recognitionResult {
                let _ = print("📱 Displaying result: \(result.name), \(result.calories) calories")
                VStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            if result.name == "Food Not Detected" || result.name == "Analysis Failed" {
                                Text("Analysis Complete")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            } else {
                                Text("Food Analysis")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                if foodRecognition.detectedFoodsCount > 1 {
                                    Text("\(foodRecognition.detectedFoodsCount) foods detected")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Check if analysis failed or timed out
                            if result.name == "Analysis Failed" {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Analysis Failed")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                    }
                                    
                                    if let errorMsg = foodRecognition.errorMessage, !errorMsg.isEmpty {
                                        Text(errorMsg)
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                    } else {
                                    Text("The analysis timed out or encountered an error.")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    }
                                    
                                    Text("Please try taking another photo.")
                                        .foregroundColor(.white.opacity(0.9))
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                            }
                            // Check if no food was detected
                            else if result.name == "Food Not Detected" || (result.name.lowercased().contains("unidentified") && result.calories == 0) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Food Not Detected")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    Text("We couldn't detect any food in this image.")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                    
                                    Text("Tips:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.top, 4)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("• Make sure food is clearly visible")
                                            .foregroundColor(.white.opacity(0.9))
                                            .font(.caption)
                                        Text("• Use good lighting")
                                            .foregroundColor(.white.opacity(0.9))
                                            .font(.caption)
                                        Text("• Get closer to the food")
                                            .foregroundColor(.white.opacity(0.9))
                                            .font(.caption)
                                        Text("• Avoid blurry photos")
                                            .foregroundColor(.white.opacity(0.9))
                                            .font(.caption)
                                    }
                                }
                            } else if result.name.lowercased().contains("unidentified") || result.calories == 0 {
                                Text("Name: \(result.name)")
                                    .foregroundColor(.white)
                                
                                Text("Unable to identify food")
                                    .foregroundColor(.orange)
                                Text("Try taking a clearer photo with better lighting")
                                    .foregroundColor(.white.opacity(0.8))
                                    .font(.caption)
                            } else {
                                Text("Name: \(result.name)")
                                    .foregroundColor(.white)
                                
                                // Show scaled calories (what actually gets logged)
                                // This matches what gets added to the daily log after portion size scaling
                                let scaledCal = Int(result.scaledCalories)
                                let originalCal = Int(result.calories)
                                
                                if scaledCal != originalCal {
                                    // Show scaled value with portion size indicator
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Calories: \(scaledCal)")
                                            .foregroundColor(.white)
                                            .fontWeight(.semibold)
                                        if let portionSize = result.portionSize, portionSize.lowercased() != "medium" {
                                            Text("(\(portionSize.capitalized) portion)")
                                                .foregroundColor(.white.opacity(0.8))
                                                .font(.caption)
                                        }
                                    }
                                } else {
                                    Text("Calories: \(scaledCal)")
                                        .foregroundColor(.white)
                                }
                                
                                // Show scaled protein (what actually gets logged)
                                Text("Protein: \(Int(result.scaledProtein))g")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        
                        HStack(spacing: 12) {
                            // Edit button - only show if food was successfully detected
                            if result.name != "Food Not Detected" && result.name != "Analysis Failed" && !result.name.lowercased().contains("unidentified") && result.calories > 0 {
                                Button(action: {
                                    // Find the most recent FoodItem that matches this result
                                    // Match by name and ensure it's from today
                                    if let matchingItem = analysis.dailyLog.todayFoodItems.first(where: { item in
                                        item.name == result.name && item.calories > 0
                                    }) {
                                        foodItemToEdit = matchingItem
                                        showingEditFoodItem = true
                                    } else {
                                        // Fallback: find the most recently added item
                                        if let mostRecent = analysis.dailyLog.todayFoodItems.first {
                                            foodItemToEdit = mostRecent
                                            showingEditFoodItem = true
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit")
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue.opacity(0.8))
                                    .cornerRadius(8)
                                }
                            }
                            
                            Button("Done") {
                                foodRecognition.recognitionResult = nil
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .padding(.bottom, 160) // Move up to avoid covering capture button (button ~70px + 30px bottom padding + recent foods ~60px = ~160px)
                }
            }
        }
        .onAppear {
            // Update selected meal type to current time-based default when view appears
            selectedMealType = FoodItem.MealType.fromTime()
        }
        .sheet(isPresented: $showingEditFoodItem) {
            if let item = foodItemToEdit {
                EditFoodItemView(
                    foodItem: item,
                    analysis: analysis,
                    onSave: {
                        showingEditFoodItem = false
                        foodItemToEdit = nil
                        // Optionally clear the recognition result after editing
                        foodRecognition.recognitionResult = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Meal Type Selector
    private var mealTypeSelector: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Toggle button (no background, larger touch area)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingMealPicker.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text(selectedMealType.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Image(systemName: showingMealPicker ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44) // Minimum touch target size
                .contentShape(Rectangle()) // Make entire area tappable
            }
            .buttonStyle(PlainButtonStyle())
            
            if showingMealPicker {
                // Dropdown menu (facing downward, anchored to top right)
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(FoodItem.MealType.allCases.enumerated()), id: \.element) { index, mealType in
                        Button(action: {
                            selectedMealType = mealType
                            showingMealPicker = false
                        }) {
                            HStack(spacing: 6) {
                                Text(mealType.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer()
                                if selectedMealType == mealType {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                } else {
                                    // Invisible spacer to maintain consistent width
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundColor(.clear)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 40) // Larger touch area
                            .frame(width: 120) // Slightly wider to fit "Breakfast" on one line
                            .contentShape(Rectangle()) // Make entire area tappable
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if index < FoodItem.MealType.allCases.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.2))
                        }
                    }
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                .padding(.top, 4)
                .fixedSize(horizontal: true, vertical: false) // Don't expand horizontally
            }
        }
    }
}
