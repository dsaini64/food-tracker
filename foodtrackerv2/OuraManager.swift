import Foundation
import Combine
import SwiftUI

/// Manages integration with Oura Ring API
class OuraManager: ObservableObject {
    static let shared = OuraManager()
    
    @Published var isConnected = false
    @Published var isAuthorizing = false
    @Published var errorMessage: String?
    @Published var todayActivity: OuraActivity?
    @Published var todaySleep: OuraSleep?
    @Published var todayReadiness: OuraReadiness?
    
    // OAuth2 Configuration
    // NOTE: These should be set in your Oura API application dashboard
    // For production, store these securely (e.g., in environment variables or secure keychain)
    private let clientId: String = "YOUR_CLIENT_ID" // Replace with your Oura Client ID
    private let clientSecret: String = "YOUR_CLIENT_SECRET" // Replace with your Oura Client Secret
    private let redirectURI = "foodtracker://oura-callback"
    private let authorizationURL = "https://cloud.ouraring.com/oauth/authorize"
    private let tokenURL = "https://api.ouraring.com/oauth/token"
    private let baseAPIURL = "https://api.ouraring.com/v2"
    
    private var accessToken: String? {
        get {
            // Store securely in Keychain in production
            return UserDefaults.standard.string(forKey: "ouraAccessToken")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ouraAccessToken")
        }
    }
    
    private var refreshToken: String? {
        get {
            return UserDefaults.standard.string(forKey: "ouraRefreshToken")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ouraRefreshToken")
        }
    }
    
    private var tokenExpiryDate: Date? {
        get {
            return UserDefaults.standard.object(forKey: "ouraTokenExpiry") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ouraTokenExpiry")
        }
    }
    
    private init() {
        // Check if we have a valid token
        if let token = accessToken, !token.isEmpty {
            // Check if token is still valid
            if let expiry = tokenExpiryDate, expiry > Date() {
                isConnected = true
                // Fetch today's data
                Task {
                    await fetchTodayData()
                }
            } else {
                // Try to refresh token
                Task {
                    await refreshAccessToken()
                }
            }
        }
    }
    
    /// Start OAuth2 authorization flow
    func startAuthorization() {
        guard clientId != "YOUR_CLIENT_ID" && clientSecret != "YOUR_CLIENT_SECRET" else {
            errorMessage = "Oura API credentials not configured. Please set Client ID and Secret in OuraManager.swift"
            return
        }
        
        isAuthorizing = true
        errorMessage = nil
        
        // Build authorization URL
        var components = URLComponents(string: authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "personal")
        ]
        
        guard let authURL = components.url else {
            errorMessage = "Failed to create authorization URL"
            isAuthorizing = false
            return
        }
        
        // Open authorization URL in Safari
        UIApplication.shared.open(authURL)
    }
    
    /// Handle OAuth callback with authorization code
    func handleCallback(url: URL) {
        guard url.scheme == "foodtracker" && url.host == "oura-callback" else {
            return
        }
        
        isAuthorizing = false
        
        // Extract authorization code from URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = "Failed to extract authorization code"
            return
        }
        
        // Exchange code for access token
        Task {
            await exchangeCodeForToken(code: code)
        }
    }
    
    /// Exchange authorization code for access token
    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: tokenURL) else {
            await MainActor.run {
                errorMessage = "Invalid token URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    errorMessage = "Failed to exchange code for token"
                }
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(OuraTokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.accessToken
                self.refreshToken = tokenResponse.refreshToken
                self.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                self.isConnected = true
                self.errorMessage = nil
            }
            
            // Fetch today's data
            await fetchTodayData()
            
        } catch {
            await MainActor.run {
                errorMessage = "Token exchange failed: \(error.localizedDescription)"
            }
        }
    }
    
    /// Refresh access token using refresh token
    private func refreshAccessToken() async {
        guard let refresh = refreshToken else {
            await MainActor.run {
                isConnected = false
            }
            return
        }
        
        guard let url = URL(string: tokenURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    isConnected = false
                    accessToken = nil
                    refreshToken = nil
                }
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(OuraTokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.accessToken
                self.refreshToken = tokenResponse.refreshToken ?? refresh
                self.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                self.isConnected = true
            }
            
        } catch {
            await MainActor.run {
                isConnected = false
            }
        }
    }
    
    /// Fetch today's activity, sleep, and readiness data
    func fetchTodayData() async {
        guard isConnected, let token = accessToken else { return }
        
        let today = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let todayString = dateFormatter.string(from: today)
        
        // Fetch all data in parallel
        async let activity = fetchActivity(date: todayString, token: token)
        async let sleep = fetchSleep(date: todayString, token: token)
        async let readiness = fetchReadiness(date: todayString, token: token)
        
        let (activityResult, sleepResult, readinessResult) = await (activity, sleep, readiness)
        
        await MainActor.run {
            if let activityData = activityResult {
                self.todayActivity = activityData
            }
            if let sleepData = sleepResult {
                self.todaySleep = sleepData
            }
            if let readinessData = readinessResult {
                self.todayReadiness = readinessData
            }
        }
    }
    
    /// Fetch activity data for a specific date
    private func fetchActivity(date: String, token: String) async -> OuraActivity? {
        guard let url = URL(string: "\(baseAPIURL)/usercollection/daily_activity?start_date=\(date)&end_date=\(date)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OuraActivityResponse.self, from: data)
            return response.data.first
        } catch {
            print("❌ Error fetching Oura activity: \(error)")
            return nil
        }
    }
    
    /// Fetch sleep data for a specific date
    private func fetchSleep(date: String, token: String) async -> OuraSleep? {
        guard let url = URL(string: "\(baseAPIURL)/usercollection/daily_sleep?start_date=\(date)&end_date=\(date)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OuraSleepResponse.self, from: data)
            return response.data.first
        } catch {
            print("❌ Error fetching Oura sleep: \(error)")
            return nil
        }
    }
    
    /// Fetch readiness data for a specific date
    private func fetchReadiness(date: String, token: String) async -> OuraReadiness? {
        guard let url = URL(string: "\(baseAPIURL)/usercollection/daily_readiness?start_date=\(date)&end_date=\(date)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OuraReadinessResponse.self, from: data)
            return response.data.first
        } catch {
            print("❌ Error fetching Oura readiness: \(error)")
            return nil
        }
    }
    
    /// Disconnect Oura account
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiryDate = nil
        isConnected = false
        todayActivity = nil
        todaySleep = nil
        todayReadiness = nil
        errorMessage = nil
    }
}

// MARK: - Oura API Models

struct OuraTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct OuraActivityResponse: Codable {
    let data: [OuraActivity]
}

struct OuraActivity: Codable {
    let id: String
    let calendarDate: String
    let totalCalories: Double?
    let activeCalories: Double?
    let steps: Int?
    let equivalentWalkingDistance: Double?
    let highActivityTime: Int?
    let mediumActivityTime: Int?
    let lowActivityTime: Int?
    let restTime: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case calendarDate = "calendar_date"
        case totalCalories = "total_calories"
        case activeCalories = "active_calories"
        case steps
        case equivalentWalkingDistance = "equivalent_walking_distance"
        case highActivityTime = "high_activity_time"
        case mediumActivityTime = "medium_activity_time"
        case lowActivityTime = "low_activity_time"
        case restTime = "rest_time"
    }
}

struct OuraSleepResponse: Codable {
    let data: [OuraSleep]
}

struct OuraSleep: Codable {
    let id: String
    let calendarDate: String
    let sleepTime: Int?
    let deepSleepTime: Int?
    let remSleepTime: Int?
    let lightSleepTime: Int?
    let sleepScore: Int?
    let efficiency: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case calendarDate = "calendar_date"
        case sleepTime = "sleep_time"
        case deepSleepTime = "deep_sleep_duration"
        case remSleepTime = "rem_sleep_duration"
        case lightSleepTime = "light_sleep_duration"
        case sleepScore = "sleep_score"
        case efficiency
    }
}

struct OuraReadinessResponse: Codable {
    let data: [OuraReadiness]
}

struct OuraReadiness: Codable {
    let id: String
    let calendarDate: String
    let score: Int?
    let temperatureDeviation: Double?
    let restingHeartRate: Double?
    let hrvBalance: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case calendarDate = "calendar_date"
        case score
        case temperatureDeviation = "temperature_deviation"
        case restingHeartRate = "resting_heart_rate"
        case hrvBalance = "hrv_balance"
    }
}
