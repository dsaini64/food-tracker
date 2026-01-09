import Foundation
import UIKit
import Combine

// MARK: - API Models
struct FoodAnalysisResponse: Codable {
    let success: Bool
    let analysisId: String
    let timestamp: String
    let analysis: FoodAnalysis
}

struct FoodAnalysis: Codable {
    let foods: [AnalyzedFood]
    let overallConfidence: Double
    let imageDescription: String
    let suggestions: [String]
    let totals: NutritionTotals?
    let insights: [String]?
    let timestamp: String?
}

// Rename this FoodItem to avoid conflicts with the main app's FoodItem model
struct AnalyzedFood: Codable, Identifiable {
    let id: String // Use String ID for API compatibility
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let servingSize: String
    let confidence: Double
    let cookingMethod: String
    let healthNotes: String?
    let verified: Bool?
    let ingredients: [String]?
    let portionSize: String?
    let macroGuess: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat, fiber
        case servingSize = "serving_size"
        case confidence
        case cookingMethod = "cooking_method"
        case healthNotes = "health_notes"
        case verified, ingredients
        case portionSize = "portion_size"
        case macroGuess = "macro_guess"
    }
}

struct NutritionTotals: Codable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
}

struct NutritionSuggestionsResponse: Codable {
    let success: Bool
    let suggestions: NutritionSuggestions
}

struct NutritionSuggestions: Codable {
    let suggestions: [String]
    let mealScore: Int
    let nextMealAdvice: String
}

// MARK: - API Error Types
enum FoodAnalysisError: Error, LocalizedError {
    case noImage
    case invalidResponse
    case networkError(Error)
    case serverError(String)
    case rateLimited
    case fileTooLarge
    case invalidFileType
    
    var errorDescription: String? {
        switch self {
        case .noImage:
            return "No image provided for analysis"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .fileTooLarge:
            return "Image file is too large. Please use a smaller image."
        case .invalidFileType:
            return "Invalid file type. Please use JPG, PNG, or WebP format."
        }
    }
}

// MARK: - Food Analysis Service
class FoodAnalysisService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastAnalysis: FoodAnalysis?
    @Published var errorMessage: String?
    
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
        // Increased timeout for ChatGPT API calls which can take 30-60 seconds
        config.timeoutIntervalForRequest = 90.0 // 90 second request timeout
        config.timeoutIntervalForResource = 120.0 // 120 second total resource timeout
        // Enable connection reuse and better TLS handling
        config.httpShouldUsePipelining = false
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // TLS configuration - support TLS 1.2 and 1.3
        if #available(iOS 13.0, *) {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        // Allow connection to Railway's SSL certificate
        config.urlCache = nil // Disable cache to avoid stale connections
        return URLSession(configuration: config)
    }()
    
    // Track if we've successfully connected before (for warmup)
    private static var hasConnectedBefore = false
    
    func analyzeFoodImage(_ image: UIImage) async throws -> FoodAnalysis {
        print("🌐 FoodAnalysisService: Starting analysis...")
        guard !isAnalyzing else {
            throw FoodAnalysisError.serverError("Analysis already in progress")
        }
        
        await MainActor.run {
            isAnalyzing = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }
        
        do {
            // Prepare the request
            let url = URL(string: "\(baseURL)/api/analyze-food")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 90.0 // Explicit 90 second timeout for food analysis
            
            // Resize image for faster processing while maintaining aspect ratio
            // Max 512px on longest side - optimized for speed (backend will resize to 512px anyway)
            // This significantly reduces upload time and processing time
            let maxDimension: CGFloat = 512
            let resizedImage = image.resizedToFit(maxDimension: maxDimension)
            
            // Convert image to JPEG data with optimized compression
            // 0.70 quality optimized for speed while maintaining food recognition accuracy
            // Matches backend quality setting for consistency
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.70) else {
                throw FoodAnalysisError.noImage
            }
            
            // Create multipart form data
            let boundary = UUID().uuidString
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"food.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Set Content-Type header BEFORE creating the body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
            
            // Use uploadTask instead of dataTask to preserve multipart Content-Type header
            // URLSession.data(for:) may modify Content-Type, but upload(for:from:) preserves it
            print("🌐 Sending request to: \(url)")
            print("🌐 Image size: \(imageData.count) bytes")
            print("🌐 Body size: \(body.count) bytes")
            print("🌐 Content-Type: multipart/form-data; boundary=\(boundary)")
            let (data, response) = try await makeRequestWithRetry(request: request, body: body, maxRetries: 2)
            print("🌐 Received response: \(response)")
            print("🌐 Response data size: \(data.count) bytes")
            
            // Log response for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 Status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("⚠️ Error response: \(errorString)")
                }
            }
            
            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FoodAnalysisError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                break
            case 400:
                let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
                if let code = errorResponse?["code"] {
                    switch code {
                    case "FILE_TOO_LARGE":
                        throw FoodAnalysisError.fileTooLarge
                    case "INVALID_FILE_TYPE":
                        throw FoodAnalysisError.invalidFileType
                    default:
                        throw FoodAnalysisError.serverError(errorResponse?["message"] ?? "Bad request")
                    }
                }
                throw FoodAnalysisError.serverError("Bad request")
            case 429:
                throw FoodAnalysisError.rateLimited
            case 500:
                throw FoodAnalysisError.serverError("Server error")
            default:
                throw FoodAnalysisError.serverError("Unexpected response: \(httpResponse.statusCode)")
            }
            
            // Decode response
            print("🌐 Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            let analysisResponse = try JSONDecoder().decode(FoodAnalysisResponse.self, from: data)
            print("🌐 Analysis successful: \(analysisResponse.analysis.foods.count) foods found")
            print("🌐 First food: \(analysisResponse.analysis.foods.first?.name ?? "No food found")")
            
            await MainActor.run {
                lastAnalysis = analysisResponse.analysis
            }
            
            return analysisResponse.analysis
            
        } catch {
            print("❌ Error in analyzeFoodImage: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error description: \(error.localizedDescription)")
            
            let analysisError: FoodAnalysisError
            if let foodError = error as? FoodAnalysisError {
                analysisError = foodError
            } else if let urlError = error as? URLError {
                print("❌ URLError code: \(urlError.code.rawValue)")
                print("❌ URLError: \(urlError.localizedDescription)")
                print("❌ URLError failure reason: \(urlError.failureURLString ?? "none")")
                
                // Handle TLS/SSL errors specifically
                if urlError.code == .secureConnectionFailed ||
                   urlError.code == .serverCertificateUntrusted ||
                   urlError.code == .serverCertificateHasBadDate ||
                   urlError.code == .serverCertificateNotYetValid ||
                   urlError.code == .clientCertificateRejected ||
                   urlError.code == .clientCertificateRequired {
                    analysisError = .serverError("SSL/TLS connection error. Please check your internet connection and try again.")
                } else if urlError.code == .timedOut {
                    analysisError = .serverError("Request timed out. The analysis is taking too long. Please try again.")
                } else if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                    analysisError = .networkError(urlError)
                } else {
                    analysisError = .networkError(urlError)
                }
            } else {
                analysisError = .networkError(error)
            }
            
            await MainActor.run {
                errorMessage = analysisError.localizedDescription
            }
            
            throw analysisError
        }
    }
    
    /// Makes a request with automatic retry for TLS/network errors
    /// This handles the common issue of TLS errors on first connection (cold start)
    private func makeRequestWithRetry(request: URLRequest, body: Data? = nil, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                // On first attempt and if we haven't connected before, add a small delay
                // This helps with Railway cold starts
                if attempt == 0 && !Self.hasConnectedBefore {
                    // Small delay to allow backend to warm up
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
                
                // Use upload(for:from:) for multipart requests to preserve Content-Type header
                // Use data(for:) for regular requests
                let result: (Data, URLResponse)
                if let body = body {
                    result = try await session.upload(for: request, from: body)
                } else {
                    result = try await session.data(for: request)
                }
                
                // Mark that we've successfully connected
                Self.hasConnectedBefore = true
                return result
                
            } catch {
                lastError = error
                
                // Check if this is a TLS/SSL error or network error that should be retried
                let isTLS = isTLSError(error)
                let shouldRetry = isRetryableError(error) && attempt < maxRetries
                
                if shouldRetry {
                    // Longer delay for TLS errors, exponential backoff for others
                    let baseDelay: Double = isTLS ? 2.0 : 0.5
                    let delay = pow(2.0, Double(attempt)) * baseDelay
                    print("🌐 Request failed (attempt \(attempt + 1)/\(maxRetries + 1)), retrying in \(delay)s... Error: \(error.localizedDescription)")
                    if let urlError = error as? URLError {
                        print("🌐 URLError code: \(urlError.code.rawValue)")
                    }
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Don't retry, throw the error
                    throw error
                }
            }
        }
        
        // If we get here, all retries failed
        throw lastError ?? FoodAnalysisError.networkError(NSError(domain: "Unknown", code: -1))
    }
    
    /// Check if error is specifically a TLS/SSL error
    private func isTLSError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .secureConnectionFailed ||
                   urlError.code == .serverCertificateUntrusted ||
                   urlError.code == .serverCertificateHasBadDate ||
                   urlError.code == .serverCertificateNotYetValid ||
                   urlError.code == .clientCertificateRejected ||
                   urlError.code == .clientCertificateRequired
        }
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("tls") ||
               errorDescription.contains("ssl") ||
               errorDescription.contains("certificate") ||
               errorDescription.contains("handshake")
    }
    
    /// Determines if an error is retryable (TLS errors, network timeouts, etc.)
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // TLS/SSL errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired,
                 NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        // Check for TLS-related error messages
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("tls") ||
           errorDescription.contains("ssl") ||
           errorDescription.contains("certificate") ||
           errorDescription.contains("handshake") {
            return true
        }
        
        return false
    }
    
    func getNutritionSuggestions(foodItems: [AnalyzedFood], userGoals: UserGoals) async throws -> NutritionSuggestions {
        let url = URL(string: "\(baseURL)/api/nutrition-suggestions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "foodItems": foodItems,
            "userGoals": [
                "goal": userGoals.goal,
                "dailyCalories": userGoals.dailyCalories,
                "proteinGoal": userGoals.proteinGoal,
                "carbGoal": userGoals.carbGoal,
                "fatGoal": userGoals.fatGoal
            ]
        ] as [String: Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw FoodAnalysisError.serverError("Failed to encode request")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FoodAnalysisError.serverError("Failed to get suggestions")
        }
        
        let suggestionsResponse = try JSONDecoder().decode(NutritionSuggestionsResponse.self, from: data)
        return suggestionsResponse.suggestions
    }
    
    // MARK: - Macro Estimation
    struct MacroEstimate: Codable {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let sugar: Double
        let sodium: Double
        let servingSize: String
        let confidence: Double
        
        enum CodingKeys: String, CodingKey {
            case name, calories, protein, carbs, fat, fiber, sugar, sodium
            case servingSize = "serving_size"
            case confidence
        }
    }
    
    struct MacroEstimateResponse: Codable {
        let success: Bool
        let estimate: MacroEstimate
    }
    
    func estimateMacros(foodName: String) async throws -> MacroEstimate {
        print("🤖 Estimating macros for: \(foodName)")
        
        let url = URL(string: "\(baseURL)/api/estimate-macros")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // ChatGPT API calls can take longer - use extended timeout
        request.timeoutInterval = 60.0 // 60 seconds for ChatGPT API
        
        let requestBody = ["foodName": foodName]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw FoodAnalysisError.serverError("Failed to encode request")
        }
        
        // Use a dedicated session with longer timeout for ChatGPT API calls
        let longTimeoutConfig = URLSessionConfiguration.default
        longTimeoutConfig.timeoutIntervalForRequest = 60.0 // 60 seconds
        longTimeoutConfig.timeoutIntervalForResource = 90.0 // 90 seconds total
        let longTimeoutSession = URLSession(configuration: longTimeoutConfig)
        
        print("🌐 Sending macro estimation request to: \(url)")
        
        do {
            let (data, response) = try await longTimeoutSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FoodAnalysisError.invalidResponse
            }
            
            print("🌐 Received response: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200:
                break
            case 400:
                let errorMsg = String(data: data, encoding: .utf8) ?? "Invalid food name"
                print("⚠️ Bad request: \(errorMsg)")
                throw FoodAnalysisError.serverError("Invalid food name")
            case 429:
                throw FoodAnalysisError.rateLimited
            case 500:
                let errorMsg = String(data: data, encoding: .utf8) ?? "Server error"
                print("⚠️ Server error: \(errorMsg)")
                throw FoodAnalysisError.serverError("Failed to estimate macros: \(errorMsg)")
            default:
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("⚠️ Unexpected status \(httpResponse.statusCode): \(errorMsg)")
                throw FoodAnalysisError.serverError("Unexpected response: \(httpResponse.statusCode)")
            }
            
            let estimateResponse = try JSONDecoder().decode(MacroEstimateResponse.self, from: data)
            print("✅ Macro estimate received: \(estimateResponse.estimate.calories) cal, \(estimateResponse.estimate.protein)g protein")
            return estimateResponse.estimate
            
        } catch let urlError as URLError {
            print("⚠️ Network error: \(urlError.localizedDescription)")
            if urlError.code == .timedOut {
                throw FoodAnalysisError.serverError("Request timed out. The ChatGPT API may be slow. Please try again.")
            } else if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                throw FoodAnalysisError.networkError(urlError)
            } else {
                throw FoodAnalysisError.networkError(urlError)
            }
        } catch {
            print("⚠️ Error estimating macros: \(error.localizedDescription)")
            if let foodError = error as? FoodAnalysisError {
                throw foodError
            } else {
                throw FoodAnalysisError.networkError(error)
            }
        }
    }
}

// MARK: - UIImage Extension for Resizing
extension UIImage {
    /// Resizes image to fit within maxDimension while maintaining aspect ratio
    /// Uses high-quality rendering for better accuracy in food recognition
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let currentSize = self.size
        let maxSize = max(currentSize.width, currentSize.height)
        
        // If image is already smaller than max dimension, return original
        guard maxSize > maxDimension else {
            return self
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / maxSize
        let newSize = CGSize(
            width: currentSize.width * scale,
            height: currentSize.height * scale
        )
        
        // Use high-quality rendering for better food recognition accuracy
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            // Use high-quality interpolation for better detail preservation
            context.cgContext.interpolationQuality = .high
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Legacy method for backward compatibility
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - User Goals Model
struct UserGoals: Codable {
    let goal: String // "weight_loss", "muscle_gain", "maintenance"
    let dailyCalories: Int
    let proteinGoal: Int
    let carbGoal: Int
    let fatGoal: Int
}

