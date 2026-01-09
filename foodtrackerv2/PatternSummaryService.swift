import Foundation
import Combine

// MARK: - Pattern Summary Models
struct PatternSummaryResponse: Codable {
    let success: Bool
    let summary: PatternSummary
}

struct PatternSummary: Codable {
    let summary: String
    let bullets: [String]
    let overall: String
}

// MARK: - Pattern Summary Service
class PatternSummaryService: ObservableObject {
    @Published var currentSummary: PatternSummary?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Track current generation task to prevent duplicates
    private var currentGenerationTask: Task<Void, Never>?
    
    // Using Railway backend in both DEBUG and RELEASE modes
    #if DEBUG
    private let baseURL = "https://precious-presence-production.up.railway.app" // Railway production backend
    // For local testing, uncomment one of these and comment out the Railway line above:
    // private let baseURL = "http://localhost:3000" // Use this for simulator testing
    // private let baseURL = "http://YOUR_MAC_IP:3000" // Replace YOUR_MAC_IP with your Mac's IP for physical device testing
    #else
    private let baseURL = "https://precious-presence-production.up.railway.app" // Railway production backend
    #endif
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Increased timeouts for ChatGPT API calls which can be slow
        // Backend has 70 second timeout, so we need at least 90 seconds here
        config.timeoutIntervalForRequest = 90.0 // Increased from 60 to 90 seconds
        config.timeoutIntervalForResource = 120.0 // Increased from 90 to 120 seconds
        return URLSession(configuration: config)
    }()
    
    func generatePatternSummary(for mealsToday: [FoodItem], retryCount: Int = 0) async {
        // Cancel any existing generation task (unless this is a retry)
        if retryCount == 0 {
            // Cancel previous task - this allows new calls with updated data to proceed
            let hadPreviousTask = currentGenerationTask != nil
            if hadPreviousTask {
                currentGenerationTask?.cancel()
                print("🔄 Cancelled previous pattern summary generation task")
                
                // Clear loading state immediately since we're cancelling and starting fresh
                // The cancelled task will also clear it in its cleanup, but this ensures
                // we can proceed immediately with the new generation
                await MainActor.run {
                    if isLoading {
                        isLoading = false
                        print("✅ Cleared loading state to allow new generation")
                    }
                }
            }
            
            // Small delay if we cancelled a previous task to let it clean up
            if hadPreviousTask {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        guard !mealsToday.isEmpty else {
            await MainActor.run {
                self.currentSummary = PatternSummary(
                    summary: "Today's Eating Pattern",
                    bullets: [
                        "No meals logged yet",
                        "Start tracking to see your eating patterns"
                    ],
                    overall: "Begin logging meals to discover your eating patterns."
                )
                self.isLoading = false
            }
            return
        }
        
        // Track this task and set loading state
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Track the current task for cancellation
        let task = Task {
        do {
            // Prepare meals data for API
            // Use ISO8601DateFormatter with timezone to preserve local time
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            dateFormatter.timeZone = TimeZone.current
            
            let mealsData = mealsToday.map { meal in
                var mealDict: [String: Any] = [
                    "timestamp": dateFormatter.string(from: meal.timestamp),
                    "ingredients": meal.ingredients ?? [],
                    "portionSize": meal.portionSize ?? "medium",
                    "mealType": meal.mealType.rawValue.lowercased(),
                    // DO NOT include macroGuess - we don't want to classify meals
                    "calories": meal.calories,
                    "carbs": meal.carbs,
                    "protein": meal.protein,
                    "fat": meal.fat
                ]
                // Only include location if it's actually provided (not nil)
                if let location = meal.location {
                    mealDict["location"] = location
                }
                // Debug logging to help identify meal type issues
                print("📊 Sending meal to backend: name='\(meal.name)', mealType='\(meal.mealType.rawValue.lowercased())', protein=\(meal.protein)g, calories=\(meal.calories)")
                return mealDict
            }
            
            // Validate data before sending
            guard let jsonData = try? JSONSerialization.data(withJSONObject: ["mealsToday": mealsData]),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw PatternSummaryError.serverError("Failed to prepare request data")
            }
            
            print("📊 Generating pattern summary for \(mealsToday.count) meals")
            
            let url = URL(string: "\(baseURL)/api/pattern-summary")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            request.timeoutInterval = 90.0 // Increased to 90 seconds to match backend timeout
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PatternSummaryError.serverError("Invalid response from server")
            }
            
            if httpResponse.statusCode != 200 {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Server error \(httpResponse.statusCode): \(errorString)")
                
                // Retry on 500 errors (server issues) or 429 (rate limit)
                if (httpResponse.statusCode == 500 || httpResponse.statusCode == 429) && retryCount < 2 {
                    print("🔄 Retrying pattern summary generation (attempt \(retryCount + 1))...")
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000)) // Exponential backoff
                    return await generatePatternSummary(for: mealsToday, retryCount: retryCount + 1)
                }
                
                throw PatternSummaryError.serverError("Server returned status \(httpResponse.statusCode): \(errorString)")
            }
            
            let summaryResponse = try JSONDecoder().decode(PatternSummaryResponse.self, from: data)
            
            // Check cancellation before updating
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoading = false
                    currentGenerationTask = nil
                }
                return
            }
            
            await MainActor.run {
                self.currentSummary = summaryResponse.summary
                self.isLoading = false
                self.errorMessage = nil
                self.currentGenerationTask = nil // Clear task reference
            }
            
        } catch let urlError as URLError {
            print("❌ Pattern Summary Network Error: \(urlError)")
            print("❌ Error code: \(urlError.code.rawValue)")
            print("❌ Error description: \(urlError.localizedDescription)")
            if let failingURL = urlError.failureURLString {
                print("❌ Failing URL: \(failingURL)")
            }
            
            // Check if it's a timeout error
            if urlError.code == .timedOut {
                print("⏱️ Request timed out after 90 seconds - backend may be slow or OpenAI API is taking too long")
                print("💡 Check backend logs to see if request was received and OpenAI API status")
            }
            
            // Retry on network errors (timeout, connection lost, etc.)
            if retryCount < 2 && (urlError.code == .timedOut || 
                                  urlError.code == .networkConnectionLost ||
                                  urlError.code == .cannotConnectToHost ||
                                  urlError.code == .notConnectedToInternet) {
                print("🔄 Retrying pattern summary generation due to network error (attempt \(retryCount + 1))...")
                // Use exponential backoff: 2s, 4s
                let delaySeconds = pow(2.0, Double(retryCount + 1))
                print("⏳ Waiting \(delaySeconds) seconds before retry...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                return await generatePatternSummary(for: mealsToday, retryCount: retryCount + 1)
            }
            
            // Check cancellation before updating
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoading = false
                    currentGenerationTask = nil
                }
                return
            }
            
            await MainActor.run {
                self.errorMessage = urlError.localizedDescription
                self.isLoading = false
                self.currentGenerationTask = nil // Clear task reference
                
                // Generate a simple fallback summary instead of error message
                self.currentSummary = PatternSummary(
                    summary: "Today's Eating Pattern",
                    bullets: generateFallbackBullets(for: mealsToday),
                    overall: generateFallbackOverall(for: mealsToday)
                )
            }
        } catch {
            print("❌ Pattern Summary Error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            // Check cancellation before updating
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoading = false
                    currentGenerationTask = nil
                }
                return
            }
            
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.currentGenerationTask = nil // Clear task reference
                
                // Generate a simple fallback summary instead of error message
                self.currentSummary = PatternSummary(
                    summary: "Today's Eating Pattern",
                    bullets: generateFallbackBullets(for: mealsToday),
                    overall: generateFallbackOverall(for: mealsToday)
                )
            }
        }
        }
        
        // Store task reference and await completion
        currentGenerationTask = task
        await task.value
    }
    
    // Generate fallback bullets based on actual data
    private func generateFallbackBullets(for meals: [FoodItem]) -> [String] {
        guard !meals.isEmpty else {
            return [
                "No meals logged yet",
                "Start tracking to see your eating patterns"
            ]
        }
        
        let totalCalories = meals.reduce(0) { $0 + $1.calories }
        let totalProtein = meals.reduce(0) { $0 + $1.protein }
        let totalCarbs = meals.reduce(0) { $0 + $1.carbs }
        let totalFat = meals.reduce(0) { $0 + $1.fat }
        
        var bullets: [String] = []
        
        // Count meals by type
        let mealTypeCounts = Dictionary(grouping: meals, by: { $0.mealType })
            .mapValues { $0.count }
        
        if let breakfastCount = mealTypeCounts[.breakfast], breakfastCount > 0 {
            bullets.append("You logged \(breakfastCount) breakfast\(breakfastCount > 1 ? " items" : " item")")
        }
        if let lunchCount = mealTypeCounts[.lunch], lunchCount > 0 {
            bullets.append("You logged \(lunchCount) lunch\(lunchCount > 1 ? " items" : " item")")
        }
        if let dinnerCount = mealTypeCounts[.dinner], dinnerCount > 0 {
            bullets.append("You logged \(dinnerCount) dinner\(dinnerCount > 1 ? " items" : " item")")
        }
        if let snackCount = mealTypeCounts[.snack], snackCount > 0 {
            bullets.append("You logged \(snackCount) snack\(snackCount > 1 ? "s" : "")")
        }
        
        if totalCalories > 0 {
            bullets.append("Total calories: \(Int(totalCalories))")
        }
        
        return bullets.isEmpty ? ["Continue logging meals to see insights"] : bullets
    }
    
    private func generateFallbackOverall(for meals: [FoodItem]) -> String {
        guard !meals.isEmpty else {
            return "Begin logging meals to discover your eating patterns."
        }
        
        let mealCount = meals.count
        if mealCount == 1 {
            return "You've logged 1 food item today."
        } else {
            return "You've logged \(mealCount) food items today."
        }
    }
}

enum PatternSummaryError: Error, LocalizedError {
    case serverError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

