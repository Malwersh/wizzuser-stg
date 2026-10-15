import WidgetKit
import SwiftUI
import ActivityKit

struct WizUserLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(context.state.statusLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("#\(context.state.orderNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(context.state.storeName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                ProgressView(value: max(0, min(1, context.state.progress)))
                    .tint(Color.orange)
                if !context.state.etaText.isEmpty {
                    Text(context.state.etaText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.statusLabel)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.etaText)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.storeName)
                            .font(.caption)
                            .lineLimit(1)
                        ProgressView(value: max(0, min(1, context.state.progress)))
                            .tint(Color.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "bag")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text(context.state.statusLabel)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "bag")
                    .foregroundColor(.orange)
            }
        }
    }
}
