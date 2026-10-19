import WidgetKit
import SwiftUI
import ActivityKit

struct WizUserLiveActivity: Widget {
    // Shared application brand accent.
    private let accent = Color(red: 0.0, green: 0.16, blue: 0.42)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
            lockScreenView(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    leadingBadge(context, size: 40)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.statusLabel)
                            .font(.headline)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Text(context.state.storeName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    etaView(context, compact: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context)
                }
            } compactLeading: {
                leadingBadge(context, size: 22)
            } compactTrailing: {
                Text(shortStatus(context))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .frame(maxWidth: 52)
            } minimal: {
                leadingBadge(context, size: 16)
            }
        }
    }

    // MARK: - Lock Screen (big, detailed card)

    private func lockScreenView(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            leadingBadge(context, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.state.statusLabel)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Spacer()
                    etaView(context, compact: false)
                }

                Text(context.state.storeName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("#\(context.state.orderNumber)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                    Spacer()
                }

                progressBar(context)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(accent)
    }

    // MARK: - Shared components

    private func progressBar(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        let progress = max(0.05, min(1, context.state.progress))
        return ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(accent)
    }

    private func isStale(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return false
    }

    private func etaView(_ context: ActivityViewContext<OrderLiveActivityAttributes>, compact: Bool) -> some View {
        let text = context.state.etaText.isEmpty ? "قيد الانتظار" : context.state.etaText
        return HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(compact ? .caption2 : .caption)
            Group {
                if isStale(context) { Text("يجري تحديث وقت الوصول") }
                else if context.state.status != "pending", let late = context.state.arrivalLatestEpoch {
                    HStack(spacing: 2) {
                        Text("تقديري")
                        if let early = context.state.arrivalEarliestEpoch, early != late {
                            Text(Date(timeIntervalSince1970: early), style: .time)
                            Text("–")
                        }
                        Text(Date(timeIntervalSince1970: late), style: .time)
                    }
                } else { Text(text) }
            }
                .font(compact ? .caption2 : .caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundColor(accent)
    }

    private func leadingBadge(_ context: ActivityViewContext<OrderLiveActivityAttributes>, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: size, height: size)
            Image(systemName: iconName(context))
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func iconName(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> String {
        switch context.state.status {
        case "pending": return "clock.fill"
        case "confirmed": return "checkmark.circle.fill"
        case "preparing": return "flame.fill"
        case "ready_for_pickup": return "takeoutbag.and.cup.and.straw.fill"
        case "assigned", "accepted", "heading_to_store", "arrived_at_store": return "bicycle"
        case "picked_up", "on_the_way", "heading_to_customer", "arrived_at_customer": return "bicycle"
        case "delivered": return "checkmark.seal.fill"
        case "cancelled", "failed", "rejected": return "xmark.circle.fill"
        default: return "bag.fill"
        }
    }

    private func shortStatus(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> String {
        let label = context.state.statusLabel
        return label.count > 12 ? String(label.prefix(12)) : label
    }
}
