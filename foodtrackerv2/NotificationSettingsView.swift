//
//  NotificationSettingsView.swift
//  foodtrackerv2
//
//  Created by Divakar Saini on 10/13/25.
//

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var userProfile: UserProfile
    @ObservedObject var notificationManager: NotificationManager
    @State private var showingTimePicker = false
    @State private var selectedMeal = ""
    
    var body: some View {
        NavigationView {
            List {
                // Notification Toggle Section
                Section {
                    Toggle("Meal Reminders", isOn: $userProfile.notificationsEnabled)
                        .onChange(of: userProfile.notificationsEnabled) { enabled in
                            if enabled {
                                notificationManager.requestNotificationPermission()
                                // Schedule notifications with current times
                                notificationManager.scheduleMealReminders(
                                    breakfastTime: userProfile.breakfastTime,
                                    lunchTime: userProfile.lunchTime,
                                    dinnerTime: userProfile.dinnerTime
                                )
                            } else {
                                notificationManager.cancelAllNotifications()
                            }
                        }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get reminded to take photos of your meals at breakfast, lunch, and dinner times.")
                }
                
                if userProfile.notificationsEnabled {
                    // Meal Times Section
                    Section {
                        MealTimeRow(
                            title: "Breakfast",
                            emoji: "🌅",
                            time: userProfile.breakfastTime,
                            onTap: {
                                selectedMeal = "breakfast"
                                showingTimePicker = true
                            }
                        )
                        
                        MealTimeRow(
                            title: "Lunch",
                            emoji: "☀️",
                            time: userProfile.lunchTime,
                            onTap: {
                                selectedMeal = "lunch"
                                showingTimePicker = true
                            }
                        )
                        
                        MealTimeRow(
                            title: "Dinner",
                            emoji: "🌙",
                            time: userProfile.dinnerTime,
                            onTap: {
                                selectedMeal = "dinner"
                                showingTimePicker = true
                            }
                        )
                    } header: {
                        Text("Meal Times")
                    } footer: {
                        Text("Tap on a meal time to customize when you receive reminders.")
                    }
                }
                
                // Permission Status Section
                Section {
                    HStack {
                        let isFullyEnabled = notificationManager.isAuthorized && userProfile.notificationsEnabled
                        Image(systemName: isFullyEnabled ? "checkmark.circle.fill" : 
                              (!notificationManager.isAuthorized ? "exclamationmark.triangle.fill" : "pause.circle.fill"))
                            .foregroundColor(isFullyEnabled ? .green : 
                                           (!notificationManager.isAuthorized ? .orange : .gray))
                        
                        VStack(alignment: .leading) {
                            Text(isFullyEnabled ? "Notifications Active" : 
                                 (!notificationManager.isAuthorized ? "Permission Required" : "Notifications Paused"))
                                .font(.headline)
                            Text(isFullyEnabled ? 
                                 "You'll receive meal reminders at your scheduled times." : 
                                 (!notificationManager.isAuthorized ? 
                                  "Tap below to enable notifications for meal reminders." :
                                  "Turn on the toggle above to receive meal reminders."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    if !notificationManager.isAuthorized {
                        Button("Enable Notifications") {
                            notificationManager.requestNotificationPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle("Notification Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingTimePicker) {
            TimePickerView(
                selectedMeal: $selectedMeal,
                userProfile: userProfile,
                notificationManager: notificationManager
            )
        }
        .onChange(of: "\(userProfile.breakfastTime.0):\(userProfile.breakfastTime.1)") { _ in
            if userProfile.notificationsEnabled && notificationManager.isAuthorized {
                notificationManager.scheduleMealReminders(
                    breakfastTime: userProfile.breakfastTime,
                    lunchTime: userProfile.lunchTime,
                    dinnerTime: userProfile.dinnerTime
                )
            }
        }
        .onChange(of: "\(userProfile.lunchTime.0):\(userProfile.lunchTime.1)") { _ in
            if userProfile.notificationsEnabled && notificationManager.isAuthorized {
                notificationManager.scheduleMealReminders(
                    breakfastTime: userProfile.breakfastTime,
                    lunchTime: userProfile.lunchTime,
                    dinnerTime: userProfile.dinnerTime
                )
            }
        }
        .onChange(of: "\(userProfile.dinnerTime.0):\(userProfile.dinnerTime.1)") { _ in
            if userProfile.notificationsEnabled && notificationManager.isAuthorized {
                notificationManager.scheduleMealReminders(
                    breakfastTime: userProfile.breakfastTime,
                    lunchTime: userProfile.lunchTime,
                    dinnerTime: userProfile.dinnerTime
                )
            }
        }
    }
}

struct MealTimeRow: View {
    let title: String
    let emoji: String
    let time: (Int, Int)
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(emoji)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(formatTime(time))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ time: (Int, Int)) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = time.0
        components.minute = time.1
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(time.0):\(String(format: "%02d", time.1))"
    }
}

struct TimePickerView: View {
    @Binding var selectedMeal: String
    @ObservedObject var userProfile: UserProfile
    @ObservedObject var notificationManager: NotificationManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedHour = 8
    @State private var selectedMinute = 0
    @State private var isAM = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Set \(selectedMeal.capitalized) Time")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                HStack(spacing: 20) {
                    // Hour Picker
                    VStack {
                        Text("Hour")
                            .font(.headline)
                        Picker("Hour", selection: $selectedHour) {
                            ForEach(1...12, id: \.self) { hour in
                                Text("\(hour)")
                                    .tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                    }
                    
                    // Minute Picker
                    VStack {
                        Text("Minute")
                            .font(.headline)
                        Picker("Minute", selection: $selectedMinute) {
                            ForEach(0..<60, id: \.self) { minute in
                                Text(String(format: "%02d", minute))
                                    .tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                    }
                    
                    // AM/PM Picker
                    VStack {
                        Text("Period")
                            .font(.headline)
                        Picker("Period", selection: $isAM) {
                            Text("AM").tag(true)
                            Text("PM").tag(false)
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                    }
                }
                .frame(height: 200)
                
                Text("Preview: \(formatSelectedTime())")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTime()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadCurrentTime()
        }
    }
    
    private func loadCurrentTime() {
        let currentTime: (Int, Int)
        switch selectedMeal {
        case "breakfast":
            currentTime = userProfile.breakfastTime
        case "lunch":
            currentTime = userProfile.lunchTime
        case "dinner":
            currentTime = userProfile.dinnerTime
        default:
            currentTime = (8, 0)
        }
        
        let hour = currentTime.0
        if hour == 0 {
            selectedHour = 12
            isAM = true
        } else if hour < 12 {
            selectedHour = hour
            isAM = true
        } else if hour == 12 {
            selectedHour = 12
            isAM = false
        } else {
            selectedHour = hour - 12
            isAM = false
        }
        
        selectedMinute = currentTime.1
    }
    
    private func formatSelectedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = isAM ? selectedHour : selectedHour + 12
        if components.hour == 12 && isAM {
            components.hour = 0
        }
        components.minute = selectedMinute
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(selectedHour):\(String(format: "%02d", selectedMinute)) \(isAM ? "AM" : "PM")"
    }
    
    private func saveTime() {
        let hour24 = isAM ? (selectedHour == 12 ? 0 : selectedHour) : (selectedHour == 12 ? 12 : selectedHour + 12)
        let newTime = (hour24, selectedMinute)
        
        switch selectedMeal {
        case "breakfast":
            userProfile.breakfastTime = newTime
        case "lunch":
            userProfile.lunchTime = newTime
        case "dinner":
            userProfile.dinnerTime = newTime
        default:
            break
        }
        
        // Reschedule notifications with new times
        notificationManager.scheduleMealReminders(
            breakfastTime: userProfile.breakfastTime,
            lunchTime: userProfile.lunchTime,
            dinnerTime: userProfile.dinnerTime
        )
    }
}

#Preview {
    NotificationSettingsView(
        userProfile: UserProfile(),
        notificationManager: NotificationManager()
    )
}
