import SwiftUI
import Combine

struct DailySummaryView: View {
    @ObservedObject var analysis: NutritionAnalysis
    @State private var showingFoodManagement = false
    @StateObject private var patternSummaryService = PatternSummaryService()
    @ObservedObject private var ouraManager = OuraManager.shared
    @State private var lastGeneratedItemIds: Set<UUID> = []
    @State private var lastMealTypeSignature: String = ""
    @State private var lastTimestampSignature: String = ""
    @State private var refreshID = UUID() // Force refresh when food items change
    @State private var isRegenerating = false // Prevent concurrent regeneration
    @State private var regenerationTask: Task<Void, Never>? // Track current regeneration task
    @State private var foodItemsObserver: AnyCancellable? // Combine observer for foodItems changes
    
    // Computed property to avoid multiple expensive calls
    private var dailySummary: DailySummary {
        analysis.generateDailySummary()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Calories Summary
                    caloriesSummarySection
                    
                    // Nutrition Overview
                    nutritionOverviewSection
                    
                    // Today's Eating Pattern (only show if there are meals logged)
                    if !analysis.dailyLog.todayFoodItems.isEmpty {
                        todayEatingPatternCard
                            .onAppear {
                                // Force regeneration when card appears to catch any missed updates
                                regeneratePatternSummaryIfNeeded()
                            }
                    }
                    
                    // Recent Food Analysis
                    recentFoodAnalysisSection
                    
                    // Meal Breakdown
                    mealBreakdownSection
                }
                .padding()
            }
            .id(refreshID) // Force refresh when food items change
            .navigationTitle("Daily Summary")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Manage Foods") {
                        showingFoodManagement = true
                    }
                }
            }
            .sheet(isPresented: $showingFoodManagement) {
                FoodManagementView(analysis: analysis)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FoodItemMealTypeUpdated"))) { _ in
                print("🔔 Received FoodItemMealTypeUpdated notification")
                // Force view refresh when food items are updated
                refreshID = UUID()
                // Clear tracking state to force regeneration since meal type changed
                lastMealTypeSignature = ""
                lastGeneratedItemIds = Set()
                // Trigger pattern regeneration with a small delay to ensure foodItems array is updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    regeneratePatternSummaryIfNeeded()
                }
            }
            // Watch for food item changes at the view level to ensure we catch all updates
            // 1. onChange watches the signature (catches updates, meal type changes)
            .onChange(of: foodItemsSignature) { newSignature in
                print("📊 Food items signature changed: \(newSignature.prefix(50))...")
                // Regenerate when food items change (any change: add, remove, update)
                regeneratePatternSummaryIfNeeded()
            }
            // 2. Also watch the published foodItems array directly (catches additions from saved foods)
            .onChange(of: analysis.dailyLog.foodItems.count) { newCount in
                print("📊 Food items count changed to: \(newCount), Today's items: \(analysis.dailyLog.todayFoodItems.count)")
                // Force regeneration by clearing tracking state
                lastMealTypeSignature = ""
                lastGeneratedItemIds = Set()
                regeneratePatternSummaryIfNeeded()
            }
            // 3. Watch todayFoodItems count directly (more reliable than computed signature)
            .onChange(of: analysis.dailyLog.todayFoodItems.count) { newCount in
                print("📊 Today's food items count changed to: \(newCount)")
                // Force regeneration by clearing tracking state
                lastMealTypeSignature = ""
                lastGeneratedItemIds = Set()
                regeneratePatternSummaryIfNeeded()
            }
            // 4. Notification listener as backup (catches FoodItemAdded notifications)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FoodItemAdded"))) { _ in
                print("🔔 Received FoodItemAdded notification")
                print("🔔 Current food items count: \(analysis.dailyLog.foodItems.count), Today's items: \(analysis.dailyLog.todayFoodItems.count)")
                // Longer delay to ensure foodItems array is fully updated and published
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("🔔 After delay - food items count: \(analysis.dailyLog.foodItems.count), Today's items: \(analysis.dailyLog.todayFoodItems.count)")
                    // Force regeneration by clearing tracking state
                    lastMealTypeSignature = ""
                    lastGeneratedItemIds = Set()
                    regeneratePatternSummaryIfNeeded()
                }
            }
            // 5. Notification listener for deletions (catches FoodItemRemoved notifications)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FoodItemRemoved"))) { _ in
                print("🔔 Received FoodItemRemoved notification")
                // Small delay to ensure foodItems array is updated before checking
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    regeneratePatternSummaryIfNeeded()
                }
            }
            .onAppear {
                // Regenerate when view appears to catch any changes that happened while view was off-screen
                print("👁️ DailySummaryView appeared, checking for pattern summary updates...")
                print("👁️ Current food items: \(analysis.dailyLog.foodItems.count), Today's items: \(analysis.dailyLog.todayFoodItems.count)")
                
                // Set up Combine publisher to watch foodItems changes directly
                // This is more reliable than onChange for computed properties
                foodItemsObserver = analysis.dailyLog.$foodItems
                    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                    .sink { _ in
                        print("📊 foodItems array changed via Combine publisher")
                        let todayCount = self.analysis.dailyLog.todayFoodItems.count
                        print("📊 Today's items count: \(todayCount)")
                        // Force regeneration by clearing tracking state
                        self.lastMealTypeSignature = ""
                        self.lastGeneratedItemIds = Set()
                        self.regeneratePatternSummaryIfNeeded()
                    }
                
                // Always force regeneration when view appears to catch any missed updates
                // Reset tracking state to force regeneration
                lastMealTypeSignature = ""
                lastGeneratedItemIds = Set()
                
                // Small delay to ensure view is fully set up
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    regeneratePatternSummaryIfNeeded()
                }
                
                // Fetch Oura data if connected
                if ouraManager.isConnected {
                    Task {
                        await ouraManager.fetchTodayData()
                    }
                }
            }
            .onDisappear {
                // Clean up observer when view disappears
                foodItemsObserver?.cancel()
                foodItemsObserver = nil
            }
        }
    }
    
    // MARK: - Today's Eating Pattern Card
    private var todayEatingPatternCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text("Today's Eating Pattern")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if patternSummaryService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let summary = patternSummaryService.currentSummary {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.bullets, id: \.self) { bullet in
                        HStack(spacing: 8) {
                            Text("•")
                                .foregroundColor(.blue)
                            Text(bullet)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if !summary.overall.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text(summary.overall)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            } else {
                Text("Generating pattern summary...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            print("📊 Pattern card appeared, forcing regeneration check...")
            // Force regeneration when card appears
            lastMealTypeSignature = ""
            lastGeneratedItemIds = Set()
            regeneratePatternSummaryIfNeeded()
        }
        .onChange(of: analysis.dailyLog.todayFoodItems.count) { newCount in
            print("📊 Pattern card detected todayFoodItems count change: \(newCount)")
            // Force regeneration when count changes
            lastMealTypeSignature = ""
            lastGeneratedItemIds = Set()
            regeneratePatternSummaryIfNeeded()
        }
    }
    
    // MARK: - Pattern Summary Helper
    // Create a stable signature for food items to watch for changes
    private var foodItemsSignature: String {
        analysis.dailyLog.todayFoodItems
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
            .map { "\($0.id.uuidString):\($0.mealType.rawValue):\(Int($0.calories)):\(Int($0.protein)):\(Int($0.carbs)):\(Int($0.fat))" }
            .joined(separator: "|")
    }
    
    private func regeneratePatternSummaryIfNeeded() {
        // Cancel any pending regeneration task - this allows rapid additions to cancel and restart
        regenerationTask?.cancel()
        
        // Create a signature that includes IDs, meal types, calories, and macros to detect any meaningful changes
        let contentSignature = foodItemsSignature
        let todayItemsCount = analysis.dailyLog.todayFoodItems.count
        let currentItemIds = Set(analysis.dailyLog.todayFoodItems.map { $0.id })
        
        print("🔄 Pattern summary check - Today's items: \(todayItemsCount), Signature: \(contentSignature.prefix(50))...")
        print("🔄 Current item IDs: \(currentItemIds), Last generated IDs: \(lastGeneratedItemIds)")
        
        // If no items exist, clear the summary immediately
        if todayItemsCount == 0 {
            print("📭 No items found - clearing pattern summary")
            patternSummaryService.currentSummary = PatternSummary(
                summary: "Today's Eating Pattern",
                bullets: [
                    "No meals logged yet",
                    "Start tracking to see your eating patterns"
                ],
                overall: "Begin logging meals to discover your eating patterns."
            )
            lastMealTypeSignature = ""
            lastGeneratedItemIds = Set()
            return
        }
        
        // Regenerate if:
        // 1. No summary exists yet, OR
        // 2. Content signature changed (items added/removed/updated), OR
        // 3. Item count changed (catches cases where signature might not detect changes), OR
        // 4. We have items but summary shows "No meals logged yet" (mismatch detection)
        let hasNoSummary = patternSummaryService.currentSummary == nil
        let signatureChanged = contentSignature != lastMealTypeSignature
        let itemIdsChanged = currentItemIds != lastGeneratedItemIds
        
        // Check if we have a mismatch: items exist but summary shows "No meals logged yet"
        let hasMismatch = todayItemsCount > 0 && 
                         patternSummaryService.currentSummary?.bullets.first == "No meals logged yet"
        
        // Always regenerate if we have items and no summary, or if IDs changed
        // This ensures we catch all additions even if signature comparison fails
        // Also regenerate if item count increased (new items added)
        let itemCountIncreased = currentItemIds.count > lastGeneratedItemIds.count
        let shouldRegenerate = hasNoSummary || itemIdsChanged || hasMismatch || signatureChanged || itemCountIncreased
        
        guard shouldRegenerate else {
            // No change detected, skip regeneration
            print("⏭️ No change detected, skipping regeneration")
            print("   - Has summary: \(!hasNoSummary)")
            print("   - Signature changed: \(signatureChanged)")
            print("   - Item IDs changed: \(itemIdsChanged)")
            print("   - Item count increased: \(itemCountIncreased)")
            print("   - Has mismatch: \(hasMismatch)")
            print("   - Current count: \(currentItemIds.count), Last count: \(lastGeneratedItemIds.count)")
            return
        }
        
        if itemCountIncreased {
            print("   Reason: Item count increased (\(lastGeneratedItemIds.count) -> \(currentItemIds.count))")
        }
        
        print("✅ Change detected, regenerating pattern summary...")
        if hasNoSummary {
            print("   Reason: No summary exists")
        }
        if signatureChanged {
            print("   Reason: Signature changed")
        }
        if itemIdsChanged {
            print("   Reason: Item IDs changed (count: \(lastGeneratedItemIds.count) -> \(currentItemIds.count))")
        }
        if hasMismatch {
            print("   Reason: Mismatch detected - have \(todayItemsCount) items but summary shows 'No meals logged yet'")
        }
        
        // Update signatures BEFORE creating task to prevent duplicate triggers
        lastMealTypeSignature = contentSignature
        lastGeneratedItemIds = currentItemIds
        
        // Create new task with debouncing
        // Note: We don't set isRegenerating here - we set it after debounce to allow rapid additions to cancel/restart
        regenerationTask = Task { @MainActor in
            // Small debounce delay to batch rapid changes
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            // Check if task was cancelled (happens when new foods are added rapidly)
            guard !Task.isCancelled else {
                print("📊 Regeneration task cancelled (new foods added during debounce)")
                return
            }
            
            // Now check if we're already generating (from PatternSummaryService's internal flag)
            // This prevents actual concurrent API calls, but allows debounced tasks to be cancelled/restarted
            guard !isRegenerating else {
                print("⚠️ Pattern summary generation already in progress, skipping duplicate call")
                return
            }
            
            // Double-check signature hasn't changed during debounce
            // Re-read current state to ensure we have the latest data
            let currentSignature = foodItemsSignature
            let currentItemIds = Set(analysis.dailyLog.todayFoodItems.map { $0.id })
            
            // If signature or IDs changed during debounce, update tracking and proceed anyway
            // This ensures we always regenerate with the latest data
            if currentSignature != lastMealTypeSignature || currentItemIds != lastGeneratedItemIds {
                print("📊 Pattern summary changed during debounce - updating tracking state")
                lastMealTypeSignature = currentSignature
                lastGeneratedItemIds = currentItemIds
            }
            
            // Always proceed with generation if we got this far (change was detected)
            // Set flag right before API call to prevent concurrent calls
            isRegenerating = true
            
            // Use current state for generation
            await patternSummaryService.generatePatternSummary(for: analysis.dailyLog.todayFoodItems)
            
            // Clear flag after generation completes
            isRegenerating = false
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("How did you do today?")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(DateFormatter.dayFormatter.string(from: Date()))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Calories Summary Section
    private var caloriesPercentage: Int {
        guard analysis.goals.dailyCalories > 0 else { return 0 }
        return Int((analysis.dailyLog.totalCalories / analysis.goals.dailyCalories) * 100)
    }
    
    private var caloriesSummarySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Daily Calories")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if analysis.goals.dailyCalories > 0 {
                    Text("\(caloriesPercentage)%")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            // Main calorie display
            HStack(spacing: 16) {
                // Consumed calories
                VStack(spacing: 6) {
                    Text("Consumed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Use adaptive font size based on number of digits
                    let caloriesValue = Int(analysis.dailyLog.totalCalories)
                    let caloriesString = "\(caloriesValue)"
                    let fontSize: CGFloat = caloriesString.count >= 4 ? 30 : 36
                    
                    Text(caloriesString)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Text("kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show Oura activity calories if available
                    if ouraManager.isConnected, let activeCal = ouraManager.todayActivity?.activeCalories {
                        Text("+ \(Int(activeCal)) active")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                
                // Divider
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 1)
                    .frame(maxHeight: 60)
                
                // Net/Remaining calories
                VStack(spacing: 6) {
                    Text(ouraManager.isConnected && ouraManager.todayActivity?.activeCalories != nil ? "Net" : "Remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Calculate net calories (consumed - active) if Oura is connected
                    let netCalories = ouraManager.isConnected && ouraManager.todayActivity?.activeCalories != nil
                        ? analysis.dailyLog.totalCalories - (ouraManager.todayActivity?.activeCalories ?? 0)
                        : remainingCalories
                    
                    // Use adaptive font size based on number of digits
                    let netValue = Int(netCalories)
                    let netString = "\(netValue)"
                    let netFontSize: CGFloat = netString.count >= 4 ? 30 : 36
                    
                    Text(netString)
                        .font(.system(size: netFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(netCalories > 0 ? .green : .orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Text("kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            
            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: analysis.caloriesProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                HStack {
                    Text("Goal: \(Int(analysis.goals.dailyCalories)) kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if analysis.goals.dailyCalories > 0 {
                        Text("\(Int(analysis.caloriesProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    } else {
                        Text("0%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var remainingCalories: Double {
        max(0, analysis.goals.dailyCalories - analysis.dailyLog.totalCalories)
    }
    
    private var progressColor: Color {
        let progress = analysis.caloriesProgress
        if progress <= 0.8 {
            return .blue
        } else if progress <= 1.0 {
            return .green
        } else {
            return .orange
        }
    }
    
    // MARK: - Nutrition Overview Section
    private var nutritionOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nutrition Overview")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                NutritionCard(
                    title: "Calories",
                    current: analysis.dailyLog.totalCalories,
                    goal: analysis.goals.dailyCalories,
                    unit: "kcal",
                    color: .blue
                )
                
                NutritionCard(
                    title: "Protein",
                    current: analysis.dailyLog.totalProtein,
                    goal: analysis.goals.dailyProtein,
                    unit: "g",
                    color: .green
                )
                
                NutritionCard(
                    title: "Carbs",
                    current: analysis.dailyLog.totalCarbs,
                    goal: analysis.goals.dailyCarbs,
                    unit: "g",
                    color: .orange
                )
                
                NutritionCard(
                    title: "Fat",
                    current: analysis.dailyLog.totalFat,
                    goal: analysis.goals.dailyFat,
                    unit: "g",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Recent Food Analysis Section
    private var recentFoodAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Food Analysis")
                .font(.headline)
            
            if analysis.dailyLog.todayFoodItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                    
                    Text("No food logged yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Take a photo to get started!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                List {
                    ForEach(Array(analysis.dailyLog.todayFoodItems.prefix(3)), id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                // Get the latest version of the item from the daily log to ensure we show updated name
                                Text(analysis.dailyLog.foodItems.first(where: { $0.id == item.id })?.name ?? item.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                let currentItem = analysis.dailyLog.foodItems.first(where: { $0.id == item.id }) ?? item
                                Text("\(Int(currentItem.calories)) cal • \(Int(currentItem.protein))g protein")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        let items = Array(analysis.dailyLog.todayFoodItems.prefix(3))
                        for index in indexSet {
                            if index < items.count {
                                analysis.dailyLog.removeFoodItem(items[index])
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .frame(height: 200)
                .id(refreshID) // Force refresh when refreshID changes
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Meal Breakdown Section
    private var mealBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal Breakdown")
                .font(.headline)
            
            ForEach(dailySummary.mealBreakdown, id: \.mealType) { breakdown in
                MealBreakdownRow(breakdown: breakdown)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Goals Status Section
    private var goalsStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goals Status")
                .font(.headline)
            
            ForEach(Array(dailySummary.goalsMet.keys.sorted()), id: \.self) { goal in
                HStack {
                    Image(systemName: dailySummary.goalsMet[goal] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(dailySummary.goalsMet[goal] == true ? .green : .red)
                    
                    Text(goal)
                        .font(.subheadline)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
}

// MARK: - Supporting Views
struct NutritionCard: View {
    let title: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color
    
    private var percentage: Int {
        guard goal > 0 else { return 0 }
        // If current is 0 or essentially 0 (less than 0.01g), return exactly 0
        guard current >= 0.01 else { return 0 }
        let roundedCurrent = round(current * 100) / 100
        guard roundedCurrent >= 0.01 else { return 0 }
        let calculatedPercentage = (roundedCurrent / goal) * 100
        return min(Int(calculatedPercentage), 999) // Cap at 999% to avoid overflow
    }
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        
        // If current is 0 or percentage is 0%, progress must be exactly 0
        if current <= 0 || percentage == 0 {
            return 0
        }
        
        // Calculate progress based on current/goal, ensuring it matches the percentage
        let roundedCurrent = round(current * 100) / 100
        let calculatedProgress = min(roundedCurrent / goal, 1.0)
        
        // Double-check: if the calculated percentage would be 0, ensure progress is 0
        let calculatedPercentage = Int((roundedCurrent / goal) * 100)
        if calculatedPercentage == 0 {
            return 0
        }
        
        return calculatedProgress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if goal > 0 {
                    Text("\(percentage)%")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Use adaptive font size for 4-digit numbers
                let currentValue = Int(current)
                let currentString = "\(currentValue)"
                let fontSize: CGFloat = currentString.count >= 4 ? 20 : 22
                
                Text(currentString)
                    .font(.system(size: fontSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Text("/ \(Int(goal)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MealBreakdownRow: View {
    let breakdown: MealBreakdown
    
    var body: some View {
        HStack {
            Text(breakdown.mealType.emoji)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(breakdown.mealType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(breakdown.calories)) calories • \(breakdown.itemCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

