import WidgetKit
import SwiftUI
import ActivityKit

struct WizUserLiveActivity: Widget {
    private let accent = Color(red: 1.0, green: 0.65, blue: 0.0) // warm orange

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
            // MARK: - Lock Screen / Notification Banner UI
            HStack(spacing: 12) {
                statusBadge(context)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(context.state.statusLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("#\(context.state.orderNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(context.state.storeName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    ProgressView(value: max(0, min(1, context.state.progress)))
                        .tint(accent)
                    if !context.state.etaText.isEmpty {
                        Text(context.state.etaText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Dynamic Island Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    statusBadge(context)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.storeName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.etaText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: max(0, min(1, context.state.progress)))
                        .tint(accent)
                }
            } compactLeading: {
                statusIcon(context)
            } compactTrailing: {
                Text(shortStatus(context))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            } minimal: {
                statusIcon(context)
            }
        }
    }

    // MARK: - Shared subviews

    @ViewBuilder
    private func statusIcon(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.2))
            Image(systemName: iconName(context))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    @ViewBuilder
    private func statusBadge(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(accent.opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: iconName(context))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    private func iconName(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> String {
        switch context.state.status {
        case "pending": return "clock"
        case "confirmed": return "checkmark.circle"
        case "preparing": return "flame"
        case "ready_for_pickup": return "takeoutbag.and.cup.and.straw"
        case "assigned", "accepted", "heading_to_store", "arrived_at_store": return "bicycle"
        case "picked_up", "on_the_way", "heading_to_customer", "arrived_at_customer": return "bicycle"
        case "delivered": return "checkmark.circle.fill"
        case "cancelled", "failed", "rejected": return "xmark.circle"
        default: return "bag"
        }
    }

    private func shortStatus(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> String {
        // Trim long Arabic labels for the tiny compact-trailing slot.
        let label = context.state.statusLabel
        return label.count > 10 ? String(label.prefix(10)) : label
    }
}
