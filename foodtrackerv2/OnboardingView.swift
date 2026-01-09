//
//  OnboardingView.swift
//  foodtrackerv2
//
//  Created by Divakar Saini on 10/13/25.
//

import SwiftUI
import UIKit
import Combine

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @StateObject private var userProfile = UserProfile()
    @State private var currentPage = 0
    @State private var selectedGender: UserProfile.Gender = .other
    @State private var age: String = ""
    @State private var wantsCustomCalorieGoal: Bool = false
    @State private var customCalorieGoal: String = ""
    
    let onboardingPages = [
        OnboardingPage(
            title: "Welcome to FoodSnap",
            subtitle: "Track your nutrition and build healthy eating habits",
            imageName: "fork.knife.circle.fill",
            color: .green
        ),
        OnboardingPage(
            title: "Snap & Track",
            subtitle: "Take photos of your meals for instant nutrition analysis",
            imageName: "camera.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Add Foods Instantly",
            subtitle: "No photo? No problem! Enter food names and let AI estimate macros for you",
            imageName: "sparkles",
            color: .orange
        ),
        OnboardingPage(
            title: "Get Insights",
            subtitle: "See detailed nutrition breakdowns and health insights",
            imageName: "chart.line.uptrend.xyaxis",
            color: .purple
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                // Welcome pages
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    OnboardingPageView(page: onboardingPages[index])
                        .tag(index)
                }
                
                // Gender selection page
                GenderSelectionView(selectedGender: $selectedGender)
                    .tag(onboardingPages.count)
                
                // Age input page
                AgeInputView(age: $age)
                    .tag(onboardingPages.count + 1)
                
                // Calorie goal preference page
                CalorieGoalPreferenceView(
                    wantsCustomCalorieGoal: $wantsCustomCalorieGoal,
                    customCalorieGoal: $customCalorieGoal,
                    gender: selectedGender,
                    age: Int(age) ?? 25,
                    userProfile: userProfile
                )
                .tag(onboardingPages.count + 2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            .onChange(of: currentPage) { oldValue, newValue in
                // When navigating to age input page, ensure keyboard appears
                if newValue == onboardingPages.count + 1 {
                    // Dismiss any existing keyboard first
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    // Then trigger focus after a delay to allow TabView animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        // Post notification to trigger focus in AgeInputView
                        NotificationCenter.default.post(name: NSNotification.Name("FocusAgeInput"), object: nil)
                    }
                }
            }
            
            // Bottom button - stays visible above keyboard
            VStack(spacing: 16) {
                if currentPage < onboardingPages.count + 2 {
                    HStack {
                        if currentPage < onboardingPages.count {
                            Button("Skip") {
                                // Skip welcome pages but still collect info
                                currentPage = onboardingPages.count
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Next") {
                            // Dismiss keyboard when moving to next page
                            if currentPage == onboardingPages.count + 1 {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            withAnimation {
                                if currentPage == onboardingPages.count + 1 && (age.isEmpty || Int(age) == nil) {
                                    // Don't proceed if age is invalid
                                    return
                                }
                                currentPage += 1
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(currentPage == onboardingPages.count + 1 && (age.isEmpty || Int(age) == nil))
                    }
                } else {
                    Button("Get Started") {
                        // Dismiss keyboard before saving
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        saveOnboardingData()
                        hasCompletedOnboarding = true
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
                    .disabled(wantsCustomCalorieGoal && (customCalorieGoal.isEmpty || Double(customCalorieGoal) == nil))
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
    
    private func saveOnboardingData() {
        // Save gender and age first
        userProfile.gender = selectedGender
        if let ageValue = Int(age) {
            userProfile.age = ageValue
        }
        
        // Save calorie goal preference
        if wantsCustomCalorieGoal, let calorieValue = Double(customCalorieGoal), calorieValue > 0 {
            userProfile.hasCustomCalorieGoal = true
            userProfile.customCalorieGoal = calorieValue
        } else {
            // Calculate and set recommended goal
            let calculatedGoal = userProfile.calculateCalorieGoal(
                gender: selectedGender,
                age: Int(age) ?? 25
            )
            userProfile.hasCustomCalorieGoal = false
            userProfile.customCalorieGoal = calculatedGoal
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: page.imageName)
                .font(.system(size: 80))
                .foregroundColor(page.color)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct OnboardingPage {
    let title: String
    let subtitle: String
    let imageName: String
    let color: Color
}

// MARK: - Gender Selection View
struct GenderSelectionView: View {
    @Binding var selectedGender: UserProfile.Gender
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "person.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("What's your gender?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("This helps us personalize your calorie goals")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                ForEach(UserProfile.Gender.allCases, id: \.self) { gender in
                    Button(action: {
                        selectedGender = gender
                    }) {
                        HStack {
                            Text(gender.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedGender == gender {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(selectedGender == gender ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Age Input View
struct AgeInputView: View {
    @Binding var age: String
    @FocusState private var isAgeFocused: Bool
    @State private var hasAppeared = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top spacing
            Spacer()
                    .frame(height: 40)
            
            Image(systemName: "calendar")
                    .font(.system(size: 60))
                .foregroundColor(.orange)
            
                VStack(spacing: 12) {
                Text("How old are you?")
                        .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 20)
                
                Text("Your age helps us calculate your daily calorie needs")
                        .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 30)
            }
            
                VStack(spacing: 16) {
                    TextField("", text: $age)
                    .keyboardType(.numberPad)
                        .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .focused($isAgeFocused)
                        .frame(maxWidth: 200)
                        .onChange(of: age) { oldValue, newValue in
                            // Limit to 3 digits
                            if newValue.count > 3 {
                                age = String(newValue.prefix(3))
                            }
                            // Dismiss keyboard when valid age is entered (2-3 digits)
                            if newValue.count >= 2 && Int(newValue) != nil {
                                // Small delay to allow the last digit to be entered
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isAgeFocused = false
                                }
                            }
                        }
                
                Text("years old")
                        .font(.title3)
                    .foregroundColor(.secondary)
            }
                .padding(.top, 20)
            
                // Bottom spacing to ensure content is visible above keyboard
            Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Use multiple attempts with increasing delays to ensure keyboard appears
            if !hasAppeared {
                hasAppeared = true
                // First attempt after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !isAgeFocused {
                        isAgeFocused = true
                    }
                }
                // Second attempt if first didn't work (TabView animation might take longer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !isAgeFocused {
                        isAgeFocused = true
                    }
                }
                // Final attempt after TabView animation should be complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if !isAgeFocused {
                        isAgeFocused = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusAgeInput"))) { _ in
            // Trigger focus when notification is received (from parent view page change)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isAgeFocused = true
            }
        }
        .onDisappear {
            // Reset when leaving the page
            hasAppeared = false
            isAgeFocused = false
        }
    }
}

// MARK: - Calorie Goal Preference View
struct CalorieGoalPreferenceView: View {
    @Binding var wantsCustomCalorieGoal: Bool
    @Binding var customCalorieGoal: String
    let gender: UserProfile.Gender
    let age: Int
    let userProfile: UserProfile
    @FocusState private var isCalorieFocused: Bool
    
    private var calculatedGoal: Double {
        userProfile.calculateCalorieGoal(gender: gender, age: age)
    }
    
    var body: some View {
        ScrollView {
        VStack(spacing: 32) {
                // Top spacing
            Spacer()
                    .frame(height: 20)
            
            Image(systemName: "target")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            VStack(spacing: 16) {
                Text("Set Your Calorie Goal")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("We've calculated a recommended goal for you")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 24) {
                // Recommended goal option
                Button(action: {
                    wantsCustomCalorieGoal = false
                    isCalorieFocused = false
                        // Dismiss keyboard
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Use Recommended Goal")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if !wantsCustomCalorieGoal {
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
                    }
                    .padding()
                    .background(!wantsCustomCalorieGoal ? Color.green.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Custom goal option
                Button(action: {
                    wantsCustomCalorieGoal = true
                        // Delay focus to allow button animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isCalorieFocused = true
                        }
                }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Set Custom Goal")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if wantsCustomCalorieGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if wantsCustomCalorieGoal {
                            TextField("Enter calories", text: $customCalorieGoal)
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
                    .background(wantsCustomCalorieGoal ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
            
                // Bottom spacing to ensure content is visible above keyboard
            Spacer()
                    .frame(height: 100)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}