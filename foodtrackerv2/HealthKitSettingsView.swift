import SwiftUI
import HealthKit

struct HealthKitSettingsView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var showingAuthorizationAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Enable/Disable Toggle
            Toggle(isOn: $healthKitManager.isEnabled) {
                HStack {
                    Label("Sync with Apple Health", systemImage: "heart.fill")
                        .foregroundColor(.red)
                }
            }
            .onChange(of: healthKitManager.isEnabled) { enabled in
                if enabled && !healthKitManager.isAuthorized {
                    // Request authorization when enabled
                    healthKitManager.requestAuthorization()
                }
            }
            
            // Status information
            if healthKitManager.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 8)
                    
                    HStack {
                        Image(systemName: healthKitManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(healthKitManager.isAuthorized ? .green : .orange)
                        
                        Text(healthKitManager.isAuthorized ? "Connected" : "Authorization Required")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    if !healthKitManager.isAuthorized {
                        Button(action: {
                            healthKitManager.requestAuthorization()
                        }) {
                            Text("Authorize HealthKit")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 4)
                    }
                    
                    Text("Your nutrition data (calories, protein, carbs, fat, fiber, sugar, sodium) will be synced to Apple Health.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }
}
