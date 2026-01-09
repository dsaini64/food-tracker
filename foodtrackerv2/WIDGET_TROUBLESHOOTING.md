# Widget Showing All Zeros - Troubleshooting Guide

## Quick Diagnostic Steps

### Step 1: Check Widget Debug Panel
1. Open your app
2. Go to **Settings** tab
3. Tap **Widget Debug**
4. Check the **App Group Status**:
   - ✅ **"Configured & Has Data"** = Good! Widget should work
   - ⚠️ **"Configured But Empty"** = App Group works but no data synced yet
   - ❌ **"Not Available"** = CRITICAL - App Group not configured

### Step 2: Check Console Logs

#### In Xcode Console, look for these patterns:

**Good signs (✅):**
```
✅ Synced to App Group: 1500 cal, 75g protein, 180g carbs, 45g fat, 5 items
✅ Widget timeline reload requested
✅ Widget successfully loaded nutrition data!
```

**Warning signs (⚠️):**
```
⚠️ App Group synchronize() returned false!
⚠️ No widget data found in App Group
⚠️ Widget loaded zero values
```

**Critical issues (❌):**
```
❌ CRITICAL: App Group not available!
❌ Widget cannot access app data without App Groups
```

## Common Issues & Solutions

### Issue 1: App Group Not Configured (❌ Not Available)

**Symptoms:**
- Widget Debug shows "❌ Not Available"
- Console shows "App Group not available"

**Solution:**
1. Open Xcode
2. Select your **main app target** (not widget)
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **App Groups**
6. Check the box for `group.com.foodtracker.app`
   - If it doesn't exist, click **+** to create it
7. Repeat steps 2-6 for your **widget extension target**
8. Clean build folder (Cmd+Shift+K)
9. Rebuild and run

**Verify:**
- Both targets should show App Groups capability
- Both should have `group.com.foodtracker.app` checked
- Check `.entitlements` files contain the group

---

### Issue 2: App Group Empty (⚠️ Configured But Empty)

**Symptoms:**
- Widget Debug shows "⚠️ Configured But Empty"
- Widget shows all zeros
- Console shows "No widget data found in App Group"

**Solution:**
1. Go to **Settings** → **Widget Debug**
2. Tap **"Force Sync Widget"**
3. Check console for:
   ```
   ✅ Force synced widget data
   📊 Verification - Read back from App Group:
     - Calories: [your value]
   ```
4. Tap **"Reload Widget Timeline"**
5. Wait 5-10 seconds for widget to refresh

**If still showing zeros:**
1. Add a food item in the app
2. Check Widget Debug again
3. Verify "Expected" values are not zero
4. If Expected values are zero, your app has no food data for today

---

### Issue 3: Data Not Syncing After Adding Food

**Symptoms:**
- You add food in the app
- Widget Debug shows old values
- Console shows no sync messages

**Solution:**
1. Check console after adding food for:
   ```
   ✅ Added food item: [name] on [date]
   🔄 Syncing widget data to App Group + Standard:
   ```

2. If you don't see these messages:
   - The `foodItems` didSet is not triggering
   - Check if food was actually added to `DailyFoodLog`

3. Manual fix:
   - Go to Widget Debug
   - Tap "Force Sync Widget"
   - This manually triggers the sync

---

### Issue 4: Widget Shows Stale Data

**Symptoms:**
- Widget shows old numbers
- App shows correct current numbers
- Widget Debug shows mismatch

**Solution:**
1. Check if values match in Widget Debug:
   - "Value" column = what widget sees
   - "Expected" column = what app has
   
2. If they don't match:
   - Tap **"Force Sync Widget"**
   - Tap **"Reload Widget Timeline"**
   - Wait 5-10 seconds

3. If still stale:
   - Remove widget from home screen (long press → Remove Widget)
   - Force quit the app
   - Relaunch app
   - Re-add widget from widget gallery

---

### Issue 5: Widget Never Updates Automatically

**Symptoms:**
- Manual sync works (Force Sync button)
- Automatic sync doesn't work
- No sync logs in console when adding food

**Solution:**

Check if WidgetKit is imported in `FoodItem.swift`:
```swift
import WidgetKit  // Should be at top
```

Check if `syncWidgetData()` calls `WidgetCenter`:
```swift
WidgetCenter.shared.reloadAllTimelines()
// Should NOT be wrapped in #if canImport(WidgetKit)
```

---

### Issue 6: Different App Group Name

**Symptoms:**
- Everything looks configured correctly
- Still shows zeros or "Not Available"

**Solution:**

Verify the App Group name matches EXACTLY in:

1. **FoodItem.swift** (line ~659):
   ```swift
   let appGroupDefaults = UserDefaults(suiteName: "group.com.foodtracker.app")
   ```

2. **FoodTrackerWidget.swift** (line ~59):
   ```swift
   let appGroupDefaults = UserDefaults(suiteName: "group.com.foodtracker.app")
   ```

3. **ContentView.swift** (multiple locations):
   ```swift
   UserDefaults(suiteName: "group.com.foodtracker.app")
   ```

4. **Xcode Capabilities** for both targets:
   - Must be `group.com.foodtracker.app`

5. **Entitlements files**:
   - Check `foodtrackerv2.entitlements`
   - Check `FoodTrackerWidgetExtension.entitlements`
   - Both should contain:
     ```xml
     <key>com.apple.security.application-groups</key>
     <array>
         <string>group.com.foodtracker.app</string>
     </array>
     ```

---

## Testing Checklist

Use this checklist to verify everything is working:

- [ ] App Group capability added to **main app target**
- [ ] App Group capability added to **widget extension target**
- [ ] Both use the same group: `group.com.foodtracker.app`
- [ ] Widget Debug shows "✅ Configured & Has Data" or "⚠️ Configured But Empty"
- [ ] Added a test food item
- [ ] Console shows "✅ Synced to App Group: [numbers]"
- [ ] Console shows "✅ Widget timeline reload requested"
- [ ] Widget Debug → Force Sync → shows verification data
- [ ] Widget Debug → values match expected values
- [ ] Widget on home screen shows correct data
- [ ] Adding new food updates widget within 10 seconds

---

## Advanced Debugging

### View All App Group Keys

Add this code temporarily in Widget Debug View's `checkAppGroup()`:

```swift
if let appGroup = appGroup {
    let allKeys = appGroup.dictionaryRepresentation()
    print("🔍 ALL App Group keys and values:")
    for (key, value) in allKeys.sorted(by: { $0.key < $1.key }) {
        if key.hasPrefix("widget_") {
            print("  \(key) = \(value)")
        }
    }
}
```

This shows exactly what's in the App Group container.

### Check Widget Extension Logs

1. In Xcode, change the scheme to run the **widget extension**:
   - Product → Scheme → FoodTrackerWidget
2. Run on device/simulator
3. Choose "Today View" when prompted
4. Check console for widget's perspective:
   ```
   📊 Widget loading data from App Group:
   ```

### Force Widget Reload from Terminal

If widget seems stuck:
```bash
# Simulate widget timeline end
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.apple.chronod"'
```

---

## Still Not Working?

If you've tried everything above and widget still shows zeros:

1. **Capture logs:**
   - Open Widget Debug
   - Tap Force Sync Widget
   - Copy all console output from Xcode
   - Look for any ❌ or ⚠️ messages

2. **Check actual values:**
   - In Widget Debug, note these values:
     - App Group Status: _______
     - Consumed Calories (Value): _______
     - Consumed Calories (Expected): _______
     - Food Count (Value): _______
     - Food Count (Expected): _______

3. **Verify App Group in both entitlements:**
   ```bash
   # In terminal, from project directory:
   grep -r "group.com.foodtracker.app" .
   ```
   Should show the group in multiple files.

4. **Nuclear option (last resort):**
   - Delete app from device/simulator
   - Clean build folder (Cmd+Shift+K)
   - Delete derived data
   - Rebuild and install fresh
   - Add widget fresh from gallery

---

## Quick Reference: Widget Update Flow

```
User adds food
    ↓
DailyFoodLog.foodItems.didSet triggers
    ↓
debouncedSyncWidgetData() called (200ms delay)
    ↓
syncWidgetData() executes
    ↓
Writes to App Group UserDefaults
    ↓
Calls synchronize()
    ↓
Verifies data was written
    ↓
WidgetCenter.shared.reloadAllTimelines()
    ↓
Widget's Provider.getTimeline() called
    ↓
Widget reads from App Group
    ↓
Widget displays new data
```

If zeros persist, the break is somewhere in this chain. Use console logs to find where it stops.
