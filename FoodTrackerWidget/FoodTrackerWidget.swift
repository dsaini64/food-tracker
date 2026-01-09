//
//  FoodTrackerWidget.swift
//  FoodTrackerWidget
//
//  Created by Divakar Saini on 12/1/25.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry {
        NutritionEntry(
            date: Date(),
            caloriesConsumed: 1200,
            caloriesGoal: 2000,
            proteinConsumed: 50,
            proteinGoal: 150,
            carbsConsumed: 120,
            carbsGoal: 250,
            fatConsumed: 30,
            fatGoal: 65,
            foodCount: 3
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> ()) {
        let entry = loadNutritionData()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> ()) {
        let currentDate = Date()
        let entry = loadNutritionData()
        
        // Refresh more frequently (every 5 minutes) to catch data updates quickly
        // Also add an immediate refresh entry in 30 seconds to catch recent updates
        let immediateRefresh = Calendar.current.date(byAdding: .second, value: 30, to: currentDate)!
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
        
        let entries = [
            entry,
            NutritionEntry(
                date: immediateRefresh,
                caloriesConsumed: entry.caloriesConsumed,
                caloriesGoal: entry.caloriesGoal,
                proteinConsumed: entry.proteinConsumed,
                proteinGoal: entry.proteinGoal,
                carbsConsumed: entry.carbsConsumed,
                carbsGoal: entry.carbsGoal,
                fatConsumed: entry.fatConsumed,
                fatGoal: entry.fatGoal,
                foodCount: entry.foodCount
            )
        ]
        
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    private func loadNutritionData() -> NutritionEntry {
        // Widget extensions CANNOT access main app's UserDefaults.standard
        // They MUST use App Groups to share data
        let appGroupDefaults = UserDefaults(suiteName: "group.com.divakar.foodsnap.app")
        
        // Check if App Group is available
        guard let appGroup = appGroupDefaults else {
            NSLog("⚠️⚠️⚠️ CRITICAL: App Group not available!")
            NSLog("⚠️⚠️⚠️ Widget cannot access app data without App Groups")
            NSLog("⚠️⚠️⚠️ Configure in Xcode: Signing & Capabilities > App Groups")
            NSLog("⚠️⚠️⚠️ Add 'group.com.divakar.foodsnap.app' to BOTH targets")
            
            // Return empty data if App Group not available
            return NutritionEntry(
                date: Date(),
                caloriesConsumed: 0,
                caloriesGoal: 2000,
                proteinConsumed: 0,
                proteinGoal: 150,
                carbsConsumed: 0,
                carbsGoal: 250,
                fatConsumed: 0,
                fatGoal: 65,
                foodCount: 0
            )
        }
        
        NSLog("✅ WIDGET: App Group UserDefaults is accessible")
        
        // Force synchronize to ensure we have latest data
        appGroup.synchronize()
        
        // Log ALL keys in the App Group to see what's actually there
        let allData = appGroup.dictionaryRepresentation()
        NSLog("🔍 WIDGET: Total keys in App Group: \(allData.keys.count)")
        NSLog("🔍 WIDGET: All keys: \(Array(allData.keys).sorted().joined(separator: ", "))")
        
        let widgetKeys = allData.keys.filter { $0.hasPrefix("widget_") }.sorted()
        NSLog("🔍 WIDGET: Widget-specific keys (\(widgetKeys.count)): \(widgetKeys.joined(separator: ", "))")
        
        // Print each widget key with its value
        for key in widgetKeys {
            if let value = allData[key] {
                NSLog("🔍 WIDGET:   \(key) = \(value)")
            }
        }
        
        // Read directly from App Group (widget can't access standard UserDefaults)
        let caloriesConsumed = appGroup.double(forKey: "widget_todayCalories")
        let proteinConsumed = appGroup.double(forKey: "widget_todayProtein")
        let carbsConsumed = appGroup.double(forKey: "widget_todayCarbs")
        let fatConsumed = appGroup.double(forKey: "widget_todayFat")
        let foodCount = appGroup.integer(forKey: "widget_foodCount")
        
        let caloriesGoal = appGroup.double(forKey: "widget_goalCalories")
        let proteinGoal = appGroup.double(forKey: "widget_goalProtein")
        let carbsGoal = appGroup.double(forKey: "widget_goalCarbs")
        let fatGoal = appGroup.double(forKey: "widget_goalFat")
        
        // Debug logging - check if keys exist and log ALL keys in App Group
        let hasCaloriesKey = appGroup.object(forKey: "widget_todayCalories") != nil
        let hasProteinKey = appGroup.object(forKey: "widget_todayProtein") != nil
        let hasCarbsKey = appGroup.object(forKey: "widget_todayCarbs") != nil
        let hasFatKey = appGroup.object(forKey: "widget_todayFat") != nil
        let hasCountKey = appGroup.object(forKey: "widget_foodCount") != nil
        let hasGoalsKey = appGroup.object(forKey: "widget_goalCalories") != nil
        
        NSLog("📊 Widget loading data from App Group:")
        NSLog("  - Keys exist: calories=\(hasCaloriesKey), protein=\(hasProteinKey), carbs=\(hasCarbsKey), fat=\(hasFatKey), count=\(hasCountKey), goals=\(hasGoalsKey)")
        NSLog("  - Consumed: \(caloriesConsumed) cal, \(proteinConsumed)g protein, \(carbsConsumed)g carbs, \(fatConsumed)g fat")
        NSLog("  - Goals: \(caloriesGoal) cal, \(proteinGoal)g protein, \(carbsGoal)g carbs, \(fatGoal)g fat")
        NSLog("  - Food count: \(foodCount)")
        
        // If no data found, log warning
        if !hasCaloriesKey && caloriesConsumed == 0 {
            NSLog("❌❌❌ WIDGET: No widget_* keys found in App Group!")
            NSLog("❌❌❌ WIDGET: This means the app is writing to a DIFFERENT App Group container")
            NSLog("❌❌❌ WIDGET: Check that BOTH targets have 'group.com.divakar.foodsnap.app' in entitlements")
        }
        
        // Verify we got valid data
        if caloriesConsumed > 0 || proteinConsumed > 0 || carbsConsumed > 0 || fatConsumed > 0 {
            NSLog("✅ Widget successfully loaded nutrition data!")
        } else {
            NSLog("⚠️ Widget loaded zero values - this might be correct if no food logged today")
        }
        
        return NutritionEntry(
            date: Date(),
            caloriesConsumed: caloriesConsumed,
            caloriesGoal: caloriesGoal > 0 ? caloriesGoal : 2000,
            proteinConsumed: proteinConsumed,
            proteinGoal: proteinGoal > 0 ? proteinGoal : 150,
            carbsConsumed: carbsConsumed,
            carbsGoal: carbsGoal > 0 ? carbsGoal : 250,
            fatConsumed: fatConsumed,
            fatGoal: fatGoal > 0 ? fatGoal : 65,
            foodCount: foodCount
        )
    }
}

// MARK: - Timeline Entry
struct NutritionEntry: TimelineEntry {
    let date: Date
    let caloriesConsumed: Double
    let caloriesGoal: Double
    let proteinConsumed: Double
    let proteinGoal: Double
    let carbsConsumed: Double
    let carbsGoal: Double
    let fatConsumed: Double
    let fatGoal: Double
    let foodCount: Int
    
    var caloriesPercentage: Double {
        caloriesGoal > 0 ? min(caloriesConsumed / caloriesGoal, 1.0) : 0
    }
    
    var caloriesRemaining: Double {
        max(caloriesGoal - caloriesConsumed, 0)
    }
}

// MARK: - Widget View
struct FoodTrackerWidgetEntryView : View {
    var entry: NutritionEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget
struct SmallWidgetView: View {
    let entry: NutritionEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Today")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Spacer(minLength: 0)
            
            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 7)
                
                Circle()
                    .trim(from: 0, to: entry.caloriesPercentage)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 1) {
                    Text("\(Int(entry.caloriesConsumed))")
                        .font(.system(size: 22, weight: .bold))
                    Text("of \(Int(entry.caloriesGoal))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 0)
            
            // Footer
            Text("\(entry.foodCount) meal\(entry.foodCount == 1 ? "" : "s") logged")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

// MARK: - Medium Widget
struct MediumWidgetView: View {
    let entry: NutritionEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Left side - Calories
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Text("Today")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Int(entry.caloriesConsumed))")
                        .font(.system(size: 28, weight: .bold))
                    Text("of \(Int(entry.caloriesGoal)) cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(value: entry.caloriesPercentage)
                    .tint(.blue)
                    .frame(height: 4)
                
                Text("\(Int(entry.caloriesRemaining)) cal left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Right side - Macros
            VStack(alignment: .leading, spacing: 8) {
                MacroRow(
                    name: "Protein",
                    consumed: entry.proteinConsumed,
                    goal: entry.proteinGoal,
                    color: .green,
                    icon: "p.circle.fill"
                )
                
                MacroRow(
                    name: "Carbs",
                    consumed: entry.carbsConsumed,
                    goal: entry.carbsGoal,
                    color: .orange,
                    icon: "c.circle.fill"
                )
                
                MacroRow(
                    name: "Fat",
                    consumed: entry.fatConsumed,
                    goal: entry.fatGoal,
                    color: .purple,
                    icon: "f.circle.fill"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: - Large Widget
struct LargeWidgetView: View {
    let entry: NutritionEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today's Nutrition")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(entry.foodCount) meal\(entry.foodCount == 1 ? "" : "s") logged")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            // Calories Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Calories")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(entry.caloriesConsumed))")
                        .font(.system(size: 32, weight: .bold))
                    Text("/ \(Int(entry.caloriesGoal))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(entry.caloriesRemaining)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                
                ProgressView(value: entry.caloriesPercentage)
                    .tint(.blue)
                    .frame(height: 5)
            }
            
            Divider()
            
            // Macros Section
            VStack(spacing: 10) {
                MacroRowLarge(
                    name: "Protein",
                    consumed: entry.proteinConsumed,
                    goal: entry.proteinGoal,
                    color: .green,
                    icon: "p.circle.fill"
                )
                
                MacroRowLarge(
                    name: "Carbs",
                    consumed: entry.carbsConsumed,
                    goal: entry.carbsGoal,
                    color: .orange,
                    icon: "c.circle.fill"
                )
                
                MacroRowLarge(
                    name: "Fat",
                    consumed: entry.fatConsumed,
                    goal: entry.fatGoal,
                    color: .purple,
                    icon: "f.circle.fill"
                )
            }
        }
        .padding(16)
    }
}

// MARK: - Supporting Views
struct MacroRow: View {
    let name: String
    let consumed: Double
    let goal: Double
    let color: Color
    let icon: String
    
    var percentage: Double {
        goal > 0 ? min(consumed / goal, 1.0) : 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 11))
                    .frame(width: 12)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                
                // Show consumed/goal inline on the right
                HStack(spacing: 2) {
                    Text("\(Int(consumed))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("/ \(Int(goal))g")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            ProgressView(value: percentage)
                .tint(color)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MacroRowLarge: View {
    let name: String
    let consumed: Double
    let goal: Double
    let color: Color
    let icon: String
    
    var percentage: Double {
        goal > 0 ? min(consumed / goal, 1.0) : 0
    }
    
    var remaining: Double {
        max(goal - consumed, 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                    .frame(width: 16)
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 3) {
                    Text("\(Int(consumed))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("/ \(Int(goal))g")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 0) {
                ProgressView(value: percentage)
                    .tint(color)
                    .frame(height: 4)
                
                Text("\(Int(remaining))g left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
    }
}

// MARK: - Widget Configuration
struct FoodTrackerWidget: Widget {
    let kind: String = "FoodTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FoodTrackerWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nutrition Tracker")
        .description("Track your daily nutrition goals at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    FoodTrackerWidget()
} timeline: {
    NutritionEntry(
        date: .now,
        caloriesConsumed: 1200,
        caloriesGoal: 2000,
        proteinConsumed: 50,
        proteinGoal: 150,
        carbsConsumed: 120,
        carbsGoal: 250,
        fatConsumed: 30,
        fatGoal: 65,
        foodCount: 3
    )
    NutritionEntry(
        date: .now,
        caloriesConsumed: 1800,
        caloriesGoal: 2000,
        proteinConsumed: 130,
        proteinGoal: 150,
        carbsConsumed: 200,
        carbsGoal: 250,
        fatConsumed: 55,
        fatGoal: 65,
        foodCount: 5
    )
}

#Preview(as: .systemMedium) {
    FoodTrackerWidget()
} timeline: {
    NutritionEntry(
        date: .now,
        caloriesConsumed: 1200,
        caloriesGoal: 2000,
        proteinConsumed: 50,
        proteinGoal: 150,
        carbsConsumed: 120,
        carbsGoal: 250,
        fatConsumed: 30,
        fatGoal: 65,
        foodCount: 3
    )
}

#Preview(as: .systemLarge) {
    FoodTrackerWidget()
} timeline: {
    NutritionEntry(
        date: .now,
        caloriesConsumed: 1200,
        caloriesGoal: 2000,
        proteinConsumed: 50,
        proteinGoal: 150,
        carbsConsumed: 120,
        carbsGoal: 250,
        fatConsumed: 30,
        fatGoal: 65,
        foodCount: 3
    )
}

