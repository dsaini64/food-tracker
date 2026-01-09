import SwiftUI
import Combine

struct HealthInsightsView: View {
    @ObservedObject var analysis: NutritionAnalysis
    @State private var selectedTimeframe: Timeframe = .week
    
    enum Timeframe: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    // MARK: - Computed Properties for Timeframe Filtering
    private var filteredFoodItems: [FoodItem] {
        let now = Date()
        let calendar = Calendar.current
        
        switch selectedTimeframe {
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return analysis.dailyLog.foodItems.filter { $0.timestamp >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return analysis.dailyLog.foodItems.filter { $0.timestamp >= monthAgo }
        case .year:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return analysis.dailyLog.foodItems.filter { $0.timestamp >= yearAgo }
        }
    }
    
    private var filteredCalories: Double {
        filteredFoodItems.reduce(0) { $0 + $1.calories }
    }
    
    private var filteredProtein: Double {
        filteredFoodItems.reduce(0) { $0 + $1.protein }
    }
    
    // Calculate number of unique days with food data
    private var daysWithData: Int {
        let calendar = Calendar.current
        let uniqueDays = Set(filteredFoodItems.map { item in
            calendar.startOfDay(for: item.timestamp)
        })
        return uniqueDays.count
    }
    
    // Food items excluding today (for averages - only completed days)
    private var completedDaysFilteredFoodItems: [FoodItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return filteredFoodItems.filter { item in
            calendar.startOfDay(for: item.timestamp) != today
        }
    }
    
    // Calculate number of unique completed days (excluding today)
    private var completedDaysWithData: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let uniqueDays = Set(completedDaysFilteredFoodItems.map { item in
            calendar.startOfDay(for: item.timestamp)
        })
        return uniqueDays.count
    }
    
    private var timeframeDescription: String {
        switch selectedTimeframe {
        case .week:
            return "Last 7 days"
        case .month:
            return "Last 30 days"
        case .year:
            return "Last 365 days"
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Timeframe Selector
                    timeframeSelector
                    
                    // Show insights or empty state
                    if !filteredFoodItems.isEmpty {
                        // Nutrition Patterns
                        nutritionPatternsSection
                    } else {
                        // Empty state - show summary even with no data
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Health Insights")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Data Yet")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Start logging food to see insights about your eating patterns")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Show basic summary even with no data
            InsightCard(
                title: "Summary",
                items: [
                    "Days tracked: 0",
                    "Total foods logged: 0",
                    "Timeframe: \(timeframeDescription)"
                ],
                icon: "chart.bar.fill",
                color: .blue
            )
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Timeframe Selector
    private var timeframeSelector: some View {
        Picker("Timeframe", selection: $selectedTimeframe) {
            ForEach(Timeframe.allCases, id: \.self) { timeframe in
                Text(timeframe.rawValue).tag(timeframe)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // Build nutrition trends items conditionally based on data availability
    private var nutritionTrendsItems: [String] {
        var items = ["Total Foods: \(filteredFoodItems.count)"]
        
        // Only show "Average Daily Calories" if there's enough data
        let shouldShowAverageCalories: Bool
        switch selectedTimeframe {
        case .week:
            // Always show for week view
            shouldShowAverageCalories = true
        case .month:
            // Need at least 7 days of data
            shouldShowAverageCalories = daysWithData >= 7
        case .year:
            // Need at least 30 days of data
            shouldShowAverageCalories = daysWithData >= 30
        }
        
        if shouldShowAverageCalories {
            // Use completed days average (excluding today) for more accurate representation
            // Only count days that actually have food entries
            if completedDaysWithData > 0 {
                let completedCalories = completedDaysFilteredFoodItems.reduce(0) { $0 + $1.calories }
                items.append("Average Daily Calories: \(String(format: "%.0f", completedCalories / Double(completedDaysWithData)))")
            } else if daysWithData > 0 {
                // Fallback: use all days with data (including today) if no completed days
                items.append("Average Daily Calories: \(String(format: "%.0f", filteredCalories / Double(daysWithData)))")
            }
            // If no days with data at all, don't show average
        }
        
        return items
    }
    
    // MARK: - Computed Properties for Insights
    
    // Helper to group food items by day and calculate daily totals
    private var dailyTotals: [(calories: Double, protein: Double, carbs: Double, fat: Double)] {
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: completedDaysFilteredFoodItems) { item in
            calendar.startOfDay(for: item.timestamp)
        }
        
        return groupedByDay.values.map { items in
            (
                calories: items.reduce(0) { $0 + $1.calories },
                protein: items.reduce(0) { $0 + $1.protein },
                carbs: items.reduce(0) { $0 + $1.carbs },
                fat: items.reduce(0) { $0 + $1.fat }
            )
        }
    }
    
    private var averageDailyCalories: Double {
        let totals = dailyTotals
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.calories } / Double(totals.count)
    }
    
    private var averageDailyProtein: Double {
        let totals = dailyTotals
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.protein } / Double(totals.count)
    }
    
    private var averageDailyCarbs: Double {
        let totals = dailyTotals
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.carbs } / Double(totals.count)
    }
    
    private var averageDailyFat: Double {
        let totals = dailyTotals
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.fat } / Double(totals.count)
    }
    
    // Most frequent foods - only shows foods eaten 2+ times
    // If all foods are unique (count = 1), this will be empty and the section won't display
    private var mostFrequentFoods: [(name: String, count: Int)] {
        let foodCounts = Dictionary(grouping: filteredFoodItems, by: { $0.name })
            .mapValues { $0.count }
            .filter { $0.value >= 2 } // Only include foods eaten 2+ times
            .sorted { $0.value > $1.value }
            .prefix(5)
        return foodCounts.map { (name: $0.key, count: $0.value) }
    }
    
    // Top protein sources - shows foods with highest protein content
    private var topProteinSources: [(name: String, protein: Double, calories: Double)] {
        let foodGroups = Dictionary(grouping: filteredFoodItems, by: { $0.name })
        
        // Calculate average protein per food (since same food might have different portions)
        let foodProtein = foodGroups.mapValues { items in
            (avgProtein: items.reduce(0) { $0 + $1.protein } / Double(items.count),
             avgCalories: items.reduce(0) { $0 + $1.calories } / Double(items.count))
        }
        
        return foodProtein
            .map { (name: $0.key, protein: $0.value.avgProtein, calories: $0.value.avgCalories) }
            .sorted { $0.protein > $1.protein }
            .prefix(5)
            .map { $0 }
    }
    
    private var mealTypeDistribution: [FoodItem.MealType: Int] {
        Dictionary(grouping: filteredFoodItems, by: { $0.categorizedMealType })
            .mapValues { $0.count }
    }
    
    private var mealTypeCalorieDistribution: [FoodItem.MealType: Double] {
        Dictionary(grouping: filteredFoodItems, by: { $0.categorizedMealType })
            .mapValues { items in
                items.reduce(0) { $0 + $1.calories }
            }
    }
    
    private var mealDistributionInsights: [String] {
        guard filteredCalories > 0 else { return [] }
        
        let calorieDist = mealTypeCalorieDistribution
        var insights: [String] = []
        
        // Calculate percentage of calories from each meal type
        let breakfastCalories = calorieDist[.breakfast] ?? 0
        let lunchCalories = calorieDist[.lunch] ?? 0
        let dinnerCalories = calorieDist[.dinner] ?? 0
        let snackCalories = calorieDist[.snack] ?? 0
        
        let breakfastPercent = Int((breakfastCalories / filteredCalories) * 100)
        let lunchPercent = Int((lunchCalories / filteredCalories) * 100)
        let dinnerPercent = Int((dinnerCalories / filteredCalories) * 100)
        let snackPercent = Int((snackCalories / filteredCalories) * 100)
        
        // Find which meal type has the most calories
        let maxMeal = calorieDist.max { $0.value < $1.value }
        if let maxMeal = maxMeal, maxMeal.value > 0 {
            let maxPercent = Int((maxMeal.value / filteredCalories) * 100)
            insights.append("\(maxMeal.key.rawValue) contained \(maxPercent)% of calories")
        }
        
        // Add other meal types if they have significant calories (>5%), avoiding duplicates
        if breakfastPercent >= 5 && maxMeal?.key != .breakfast {
            insights.append("Breakfast: \(breakfastPercent)% of calories")
        }
        if lunchPercent >= 5 && maxMeal?.key != .lunch {
            insights.append("Lunch: \(lunchPercent)% of calories")
        }
        if dinnerPercent >= 5 && maxMeal?.key != .dinner {
            insights.append("Dinner: \(dinnerPercent)% of calories")
        }
        if snackPercent >= 5 && maxMeal?.key != .snack {
            insights.append("Snacks: \(snackPercent)% of calories")
        }
        
        return insights
    }
    
    private var mostActiveMeal: String {
        let distribution = mealTypeDistribution
        let maxMeal = distribution.max { $0.value < $1.value }
        return maxMeal?.key.rawValue ?? "N/A"
    }
    
    private var averageItemsPerDay: Double {
        guard completedDaysWithData > 0 else { return 0 }
        return Double(completedDaysFilteredFoodItems.count) / Double(completedDaysWithData)
    }
    
    private var totalDaysTracked: Int {
        daysWithData
    }
    
    // MARK: - Nutrition Patterns Section
    private var nutritionPatternsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overview Section
            if daysWithData > 0 {
                InsightCard(
                    title: "Overview",
                    items: {
                        var items = [
                        "Days tracked: \(totalDaysTracked)",
                        "Total foods logged: \(filteredFoodItems.count)"
                        ]
                        
                        // Add average calories per day if we have data
                        if averageDailyCalories > 0 {
                            items.append("Average calories per day: \(String(format: "%.0f", averageDailyCalories)) cal")
                        }
                        
                        items.append("Average items per day: \(String(format: "%.1f", averageItemsPerDay))")
                        
                        return items
                    }(),
                    icon: "chart.bar.fill",
                    color: .blue
                )
            }
            
            // Daily Averages Section
            if daysWithData >= 3 {
                InsightCard(
                    title: "Daily Averages",
                    items: [
                        "Calories: \(String(format: "%.0f", averageDailyCalories)) cal",
                        "Protein: \(String(format: "%.1f", averageDailyProtein))g",
                        "Carbs: \(String(format: "%.1f", averageDailyCarbs))g",
                        "Fat: \(String(format: "%.1f", averageDailyFat))g"
                    ],
                    icon: "chart.pie.fill",
                    color: .green
                )
    }
    
            // Calorie Distribution Across Meals
            if !mealDistributionInsights.isEmpty {
                InsightCard(
                    title: "Calorie Distribution",
                    items: mealDistributionInsights,
                    icon: "chart.pie.fill",
                    color: .orange
                )
            }
                    
            // Most Frequent Foods - only show if there are foods eaten 2+ times
            // If all foods are unique, this section won't appear
            if !mostFrequentFoods.isEmpty {
                InsightCard(
                    title: "Most Frequent Foods",
                    items: mostFrequentFoods.map { "\($0.name): \($0.count) times" },
                    icon: "star.fill",
                    color: .purple
                        )
            }
            
            // Top Protein Sources - only show if there are foods with significant protein
            let significantProtein = topProteinSources.filter { $0.protein >= 10 }
            if !significantProtein.isEmpty {
                InsightCard(
                    title: "Top Protein Sources",
                    items: significantProtein.prefix(5).map { food in
                        "\(food.name): \(String(format: "%.1f", food.protein))g protein"
                    },
                    icon: "dumbbell.fill",
                    color: .blue
                        )
            }
            
            // Eating Patterns
            if daysWithData >= 3 {
                InsightCard(
                    title: "Eating Patterns",
                    items: [
                        "Most active meal: \(mostActiveMeal)",
                        "Average items per day: \(String(format: "%.1f", averageItemsPerDay))"
                    ],
                    icon: "chart.line.uptrend.xyaxis",
                    color: .red
                )
    }
        }
    }
    
}

// MARK: - Supporting Views
struct TrendCard: View {
    let title: String
    let currentValue: Double
    let previousValue: Double
    let unit: String
    let color: Color
    
    private var trend: Double {
        currentValue - previousValue
    }
    
    private var trendIcon: String {
        trend > 0 ? "arrow.up.right" : "arrow.down.right"
    }
    
    private var trendColor: Color {
        trend > 0 ? .green : .red
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("\(String(format: "%.1f", currentValue))\(unit)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                    
                    HStack(spacing: 2) {
                        Image(systemName: trendIcon)
                            .font(.caption)
                        Text("\(String(format: "%.1f", abs(trend)))\(unit)")
                            .font(.caption)
                    }
                    .foregroundColor(trendColor)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InsightCard: View {
    let title: String
    let items: [String]
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(item)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PatternCard: View {
    let title: String
    let items: [String]
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct RecommendationCard: View {
    let title: String
    let description: String
    let action: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(action)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
