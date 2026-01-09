//
//  FoodTrackerWidgetLiveActivity.swift
//  FoodTrackerWidget
//
//  Created by Divakar Saini on 12/1/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FoodTrackerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FoodTrackerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FoodTrackerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FoodTrackerWidgetAttributes {
    fileprivate static var preview: FoodTrackerWidgetAttributes {
        FoodTrackerWidgetAttributes(name: "World")
    }
}

extension FoodTrackerWidgetAttributes.ContentState {
    fileprivate static var smiley: FoodTrackerWidgetAttributes.ContentState {
        FoodTrackerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FoodTrackerWidgetAttributes.ContentState {
         FoodTrackerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FoodTrackerWidgetAttributes.preview) {
   FoodTrackerWidgetLiveActivity()
} contentStates: {
    FoodTrackerWidgetAttributes.ContentState.smiley
    FoodTrackerWidgetAttributes.ContentState.starEyes
}
