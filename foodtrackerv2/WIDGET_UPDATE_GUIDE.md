# Widget Auto-Update System

## Overview
Your food tracker app now has an **automatic widget update system** that ensures the widget is refreshed whenever new food is added, regardless of the source (photo, saved food, custom food, etc.).

## How It Works

### Automatic Updates
The widget automatically updates when:
- ✅ A food item is added from a photo (camera or photo library)
- ✅ A saved food is logged to your daily intake
- ✅ A custom food is created and logged
- ✅ A food item is removed/deleted
- ✅ Any change is made to the food items list

### Technical Implementation

#### 1. **DailyFoodLog Observable Pattern** (`FoodItem.swift`)
```swift
class DailyFoodLog: ObservableObject {
    @Published var foodItems: [FoodItem] = [] {
        didSet {
            saveFoodItems()
            debouncedSyncWidgetData()  // <-- Automatic widget sync
            cleanupOldData()
        }
    }
}
```

Whenever `foodItems` changes (add, remove, update), the `didSet` observer automatically:
1. Saves the data to persistent storage
2. Triggers a debounced widget sync (waits 200ms to batch rapid changes)
3. Cleans up old data

#### 2. **Debounced Widget Sync**
The system uses intelligent debouncing to prevent excessive widget updates:
```swift
private func debouncedSyncWidgetData() {
    syncWidgetTimer?.invalidate()
    syncWidgetTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
        self?.syncWidgetData()
    }
}
```

This means if you add multiple foods quickly, the widget only refreshes once after you're done.

#### 3. **Widget Data Sync** (`syncWidgetData()`)
The sync process:
1. Calculates today's totals (calories, protein, carbs, fat, food count)
2. Writes to **App Group shared container** (`group.com.foodtracker.app`)
3. Verifies all writes succeeded
4. Requests widget timeline reload via `WidgetCenter.shared.reloadAllTimelines()`
5. Performs final verification

#### 4. **App Group Configuration**
The app uses an App Group container to share data between the main app and widget:
- **App Group ID**: `group.com.foodtracker.app`
- **Shared Keys**:
  - `widget_todayCalories` - Today's total calories
  - `widget_todayProtein` - Today's total protein (g)
  - `widget_todayCarbs` - Today's total carbs (g)
  - `widget_todayFat` - Today's total fat (g)
  - `widget_foodCount` - Number of foods logged today
  - `widget_goalCalories` - Daily calorie goal
  - `widget_goalProtein` - Daily protein goal (g)
  - `widget_goalCarbs` - Daily carbs goal (g)
  - `widget_goalFat` - Daily fat goal (g)

## Where Updates Are Triggered

### Automatic Triggers (via `foodItems` didSet)
1. **Adding food from camera** - `SnapchatCameraView.swift`
   - When photo is analyzed and food is added
   
2. **Adding saved food** - `SavedFoodsView.swift`
   - When user selects a saved food to log

3. **Adding custom food** - `CustomFoodCreatorView.swift`
   - When user creates and saves a custom food

4. **Removing food** - Any view with delete functionality
   - When user removes a food item

### Manual Update Methods
The app also provides manual sync methods for special cases:

1. **ContentView** - `syncGoalsToWidget()`
   - Triggered when user profile changes (age, gender, goals)
   - Also syncs current consumed data

2. **ContentView** - `syncWidgetDataManually()`
   - Force sync on app launch
   - Ensures widget has latest data even if app was terminated

3. **SettingsView** - `WidgetDebugView`
   - Debug panel for troubleshooting widget sync
   - Allows manual force sync and timeline reload

## Debugging Widget Updates

### Using Widget Debug View
1. Go to **Settings** tab
2. Tap **Widget Debug** (only visible when analysis data is available)
3. View current widget data vs expected data
4. Use action buttons:
   - **Refresh Data** - Re-read widget data from App Group
   - **Force Sync Widget** - Manually sync current data to widget
   - **Reload Widget Timeline** - Request widget refresh

### Console Logging
The system provides extensive logging:
```
✅ Synced to App Group: 1500 cal, 75g protein, 180g carbs, 45g fat, 5 items
✅ Widget timeline reload requested (after sync delay)
✅ Final verification passed: All macros synced correctly
```

Look for these emoji patterns:
- 🔄 - Syncing data
- ✅ - Success
- ⚠️ - Warning/verification issue
- ❌ - Error

## Troubleshooting

### Widget Not Updating?

1. **Check App Group Configuration**
   - Xcode → Target → Signing & Capabilities
   - Ensure App Groups capability is enabled
   - Verify `group.com.foodtracker.app` is added to both:
     - Main app target
     - Widget extension target

2. **Check Widget Debug Panel**
   - Settings → Widget Debug
   - Verify "App Group Status" shows "✅ Configured"
   - Check if widget data matches expected values

3. **Force Sync**
   - Settings → Widget Debug → Force Sync Widget
   - This manually writes data and reloads widget

4. **Remove and Re-add Widget**
   - Long press on widget
   - Remove widget
   - Re-add widget from widget gallery

### Common Issues

**Issue**: Widget shows old data
- **Solution**: Use Force Sync in Widget Debug panel

**Issue**: Widget shows zeros
- **Solution**: Check App Group configuration, ensure both targets have the same group ID

**Issue**: Widget doesn't appear
- **Solution**: Check if widget extension is included in build scheme

## Architecture Benefits

### 1. **Automatic Updates**
No need to manually call widget update code - it happens automatically whenever data changes.

### 2. **Debouncing**
Multiple rapid changes are batched into a single widget update, improving performance.

### 3. **Verification**
Every sync includes read-back verification to ensure data was written correctly.

### 4. **Retry Logic**
If verification fails, the system automatically retries the sync.

### 5. **Dual Storage**
Data is written to both App Group (for widget) and standard UserDefaults (for debugging), ensuring maximum compatibility.

## Summary

Your food tracker's widget update system is **fully automatic** and requires no manual intervention. Simply add, edit, or remove food items anywhere in your app, and the widget will update automatically within ~0.3 seconds (200ms debounce + 100ms sync delay).

The system is robust, includes verification and retry logic, and provides comprehensive debugging tools for troubleshooting.
