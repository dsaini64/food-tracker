//
//  SettingsView.swift
//  foodtrackerv2
//
//  Created by Divakar Saini
//

import SwiftUI
import HealthKit

struct SettingsView: View {
    @ObservedObject var userProfile: UserProfile
    @ObservedObject var notificationManager: NotificationManager
    @State private var showingNotificationSettings = false
    
    init(userProfile: UserProfile, notificationManager: NotificationManager) {
        self.userProfile = userProfile
        self.notificationManager = notificationManager
    }
    
    var body: some View {
        NavigationView {
            List {
                // Profile Section
                Section {
                    // Gender
                    NavigationLink(destination: GenderEditView(userProfile: userProfile)) {
                        HStack {
                            Label("Gender", systemImage: "person.fill")
                            Spacer()
                            Text(userProfile.gender.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Age
                    NavigationLink(destination: AgeEditView(userProfile: userProfile)) {
                        HStack {
                            Label("Age", systemImage: "calendar")
                            Spacer()
                            Text("\(userProfile.age) years")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Calorie Goal
                    NavigationLink(destination: CalorieGoalEditView(userProfile: userProfile)) {
                        HStack {
                            Label("Daily Calorie Goal", systemImage: "target")
                            Spacer()
                            Text("\(Int(userProfile.dailyCalorieGoal)) cal")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Your profile information helps personalize your nutrition goals.")
                }
                
                // Notifications Section
                Section {
                    Button(action: {
                        showingNotificationSettings = true
                    }) {
                        HStack {
                            Label("Notification Settings", systemImage: "bell.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Notifications")
                }
                
                // HealthKit Section
                if HKHealthStore.isHealthDataAvailable() {
                    Section {
                        HealthKitSettingsView()
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Sync your nutrition data with Apple Health. All logged foods will be automatically saved to HealthKit.")
                    }
                }
                
                // Oura Ring Section
                Section {
                    OuraSettingsView()
                } header: {
                    Text("Oura Ring")
                } footer: {
                    Text("Connect your Oura Ring to see activity calories, steps, sleep quality, and readiness scores integrated with your nutrition tracking.")
                }
                
                // Disclaimer Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nutrition recommendations are based on established dietary guidelines and are for informational purposes only. They are not intended as personalized medical advice. Consult with a healthcare provider or registered dietitian for advice tailored to your specific health needs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sources:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Button(action: {
                                    if let url = URL(string: "https://www.dietaryguidelines.gov/") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("CDC Dietary Guidelines for Americans")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    if let url = URL(string: "https://www.nal.usda.gov/fnic/interactiveDRI/") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("USDA DRI Calculator - Estimated Calorie Needs")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    if let url = URL(string: "https://www.nap.edu/catalog/10490/dietary-reference-intakes-for-energy-carbohydrate-fiber-fat-fatty-acids-cholesterol-protein-and-amino-acids") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text("Dietary Reference Intakes - Macronutrient Recommendations (DRI)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("Mifflin-St Jeor Equation (BMR)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("About Recommendations")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView(
                userProfile: userProfile,
                notificationManager: notificationManager
            )
        }
    }
}

// MARK: - Gender Edit View
struct GenderEditView: View {
    @ObservedObject var userProfile: UserProfile
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(UserProfile.Gender.allCases, id: \.self) { gender in
                Button(action: {
                    userProfile.gender = gender
                    // Reset to recommended calorie goal when gender changes
                    // User can still override with custom goal in settings
                    userProfile.hasCustomCalorieGoal = false
                    dismiss()
                }) {
                    HStack {
                        Text(gender.displayName)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if userProfile.gender == gender {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Gender")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Age Edit View
struct AgeEditView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var ageText: String
    @FocusState private var isAgeFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _ageText = State(initialValue: "\(userProfile.age)")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("How old are you?")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            TextField("Enter your age", text: $ageText)
                .keyboardType(.numberPad)
                .font(.system(size: 48, weight: .bold))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .focused($isAgeFocused)
                .padding(.horizontal)
            
            Text("years old")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Save") {
                if let ageValue = Int(ageText), ageValue > 0 && ageValue < 150 {
                    userProfile.age = ageValue
                    // Reset to recommended calorie goal when age changes
                    // User can still override with custom goal in settings
                    userProfile.hasCustomCalorieGoal = false
                    dismiss()
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background((Int(ageText) != nil && Int(ageText)! > 0 && Int(ageText)! < 150) ? Color.blue : Color.gray)
            .cornerRadius(12)
            .padding(.horizontal)
            .disabled(Int(ageText) == nil || Int(ageText)! <= 0 || Int(ageText)! >= 150)
        }
        .padding()
        .navigationTitle("Age")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isAgeFocused = true
        }
    }
}

// MARK: - Calorie Goal Edit View
struct CalorieGoalEditView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var wantsCustomGoal: Bool
    @State private var customGoalText: String
    @FocusState private var isCalorieFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    private var calculatedGoal: Double {
        userProfile.calculateCalorieGoal(gender: userProfile.gender, age: userProfile.age)
    }
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _wantsCustomGoal = State(initialValue: userProfile.hasCustomCalorieGoal)
        _customGoalText = State(initialValue: userProfile.hasCustomCalorieGoal ? "\(Int(userProfile.customCalorieGoal))" : "")
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Set Your Calorie Goal")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            VStack(spacing: 16) {
                // Recommended goal option
                Button(action: {
                    wantsCustomGoal = false
                    isCalorieFocused = false
                }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Use Recommended Goal")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if !wantsCustomGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("\(Int(calculatedGoal)) calories per day")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        
                        Text("Based on your gender and age")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(!wantsCustomGoal ? Color.green.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Custom goal option
                Button(action: {
                    wantsCustomGoal = true
                    isCalorieFocused = true
                }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Set Custom Goal")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if wantsCustomGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if wantsCustomGoal {
                            TextField("Enter calories", text: $customGoalText)
                                .keyboardType(.numberPad)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .focused($isCalorieFocused)
                        } else {
                            Text("Tap to enter your own goal")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(wantsCustomGoal ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Save") {
                userProfile.hasCustomCalorieGoal = wantsCustomGoal
                if wantsCustomGoal, let calorieValue = Double(customGoalText), calorieValue > 0 {
                    userProfile.customCalorieGoal = calorieValue
                } else {
                    userProfile.hasCustomCalorieGoal = false
                }
                dismiss()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background((!wantsCustomGoal || (Double(customGoalText) != nil && Double(customGoalText)! > 0)) ? Color.blue : Color.gray)
            .cornerRadius(12)
            .padding(.horizontal)
            .disabled(wantsCustomGoal && (customGoalText.isEmpty || Double(customGoalText) == nil || Double(customGoalText)! <= 0))
        }
        .padding()
        .navigationTitle("Calorie Goal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView(
        userProfile: UserProfile(),
        notificationManager: NotificationManager()
    )
}

