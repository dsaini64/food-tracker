import SwiftUI

struct OuraSettingsView: View {
    @ObservedObject private var ouraManager = OuraManager.shared
    @State private var showingDisconnectAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            if ouraManager.isConnected {
                // Connected state
                HStack {
                    Label("Connected to Oura Ring", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Spacer()
                    Button("Disconnect") {
                        showingDisconnectAlert = true
                    }
                    .foregroundColor(.red)
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Show today's data if available
                if let activity = ouraManager.todayActivity {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's Activity")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        if let activeCal = activity.activeCalories {
                            HStack {
                                Text("Active Calories:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(activeCal)) cal")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let steps = activity.steps {
                            HStack {
                                Text("Steps:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(steps)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                if let sleep = ouraManager.todaySleep {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Night's Sleep")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        if let sleepScore = sleep.sleepScore {
                            HStack {
                                Text("Sleep Score:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(sleepScore)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let sleepTime = sleep.sleepTime {
                            HStack {
                                Text("Sleep Duration:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(sleepTime / 3600)h \(sleepTime % 3600 / 60)m")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                if let readiness = ouraManager.todayReadiness {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Readiness Score")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        if let score = readiness.score {
                            HStack {
                                Text("Score:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(score)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                Button(action: {
                    Task {
                        await ouraManager.fetchTodayData()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Data")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.top, 8)
                
            } else {
                // Not connected state
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        ouraManager.startAuthorization()
                    }) {
                        HStack {
                            Image(systemName: "link")
                            Text("Connect Oura Ring")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .disabled(ouraManager.isAuthorizing)
                    
                    if ouraManager.isAuthorizing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Connecting...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    Text("Connect your Oura Ring to see activity calories, steps, sleep quality, and readiness scores in your daily summary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            
            if let error = ouraManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
        .alert("Disconnect Oura Ring", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                ouraManager.disconnect()
            }
        } message: {
            Text("Are you sure you want to disconnect your Oura Ring? You'll need to reconnect to sync data again.")
        }
    }
}
