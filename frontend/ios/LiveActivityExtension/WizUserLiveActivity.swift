import WidgetKit
import SwiftUI
import ActivityKit

struct WizUserLiveActivity: Widget {
    // Shared application brand accent.
    private let accent = Color(red: 0.0, green: 0.16, blue: 0.42)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
            lockScreenView(context)
                .widgetURL(URL(string: "wizuser://orders/\(context.attributes.orderId)"))
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
                    .foregroundColor(Color(red: 1, green: 0.77, blue: 0))
                    .lineLimit(1)
                    .frame(maxWidth: 52)
            } minimal: {
                leadingBadge(context, size: 16)
            }
            .widgetURL(URL(string: "wizuser://orders/\(context.attributes.orderId)"))
        }
    }

    // MARK: - Lock Screen (big, detailed card)

    private func lockScreenView(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 8) {
                    Image("WizzLiveLogo")
                        .resizable().scaledToFit()
                        .frame(width: 40, height: 40)
                        .accessibilityLabel("ويز")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.storeName)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text("#\(context.state.orderNumber)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("الوصول المتوقع")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    etaView(context, compact: false)
                }
                .frame(maxWidth: 164, alignment: .trailing)
            }
            Text(context.state.statusLabel)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(accent)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            milestones(context)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar_IQ"))
        .foregroundColor(Color(red: 0.07, green: 0.12, blue: 0.22))
        .activityBackgroundTint(.white)
        .activitySystemActionForegroundColor(accent)
    }

    /// Milestones follow the actual fulfillment status, independently of ETA.
    private func milestoneIndex(_ status: String) -> Int {
        switch status {
        case "delivered", "returned": return 3
        case "returning": return 1
        case "return_arrived": return 2
        case "picked_up", "on_the_way", "heading_to_customer", "arrived_at_customer": return 2
        case "confirmed", "preparing", "ready_for_pickup", "assigned", "accepted", "heading_to_store", "arrived_at_store": return 1
        default: return 0
        }
    }

    private func milestones(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        let current = milestoneIndex(context.state.status)
        let returning = ["returning", "return_arrived", "returned"].contains(context.state.status)
        let symbols = returning ? ["exclamationmark", "bicycle", "storefront.fill", "checkmark"] : ["checkmark", "storefront.fill", "bicycle", "house.fill"]
        let labels = returning ? ["تعذر التسليم", "العودة", "المطعم", "تأكيد الاستلام"] : ["تأكيد الطلب", "المطعم", "في الطريق", "التسليم"]
        let yellow = Color(red: 1, green: 0.77, blue: 0)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4) { index in
                if index > 0 {
                    Capsule()
                        .fill(index <= current ? accent : accent.opacity(0.12))
                        .frame(height: 4)
                        .padding(.top, 15)
                        .padding(.horizontal, 3)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 5) {
                    Image(systemName: symbols[index])
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(index == current ? accent : (index < current ? .white : accent.opacity(0.35)))
                        .frame(width: 34, height: 34)
                        .background(index == current ? yellow : (index < current ? accent : accent.opacity(0.07)), in: Circle())
                    Text(labels[index])
                        .font(.system(size: 9, weight: index == current ? .bold : .medium))
                        .foregroundColor(index <= current ? accent : .secondary)
                        .lineLimit(1)
                }
                .frame(width: 58)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Shared components

    private func progressBar(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> some View {
        let progress = max(0.05, min(1, context.state.progress))
        return ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(Color(red: 1, green: 0.77, blue: 0))
    }

    private func isStale(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return false
    }

    private func etaView(_ context: ActivityViewContext<OrderLiveActivityAttributes>, compact: Bool) -> some View {
        let text = context.state.etaText.isEmpty ? "قيد الانتظار" : context.state.etaText
        return Group {
            if ["returning", "return_arrived", "returned"].contains(context.state.status) {
                Text(text)
            } else if isStale(context) {
                Text("جارٍ تحديث الوصول")
            } else if context.state.status != "pending", let late = context.state.arrivalLatestEpoch {
                HStack(spacing: 3) {
                    if let early = context.state.arrivalEarliestEpoch, early != late {
                        Text(Date(timeIntervalSince1970: early), style: .time)
                        Text("–")
                    }
                    Text(Date(timeIntervalSince1970: late), style: .time)
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                Text(text)
            }
        }
        .font(.system(size: compact ? 10 : 13, weight: .bold))
        .foregroundColor(compact ? Color.white : accent)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .multilineTextAlignment(.trailing)
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
        case "returning": return "arrow.uturn.backward.circle.fill"
        case "return_arrived": return "storefront.fill"
        case "returned", "delivered": return "checkmark.seal.fill"
        case "cancelled", "failed", "rejected": return "xmark.circle.fill"
        default: return "bag.fill"
        }
    }

    private func shortStatus(_ context: ActivityViewContext<OrderLiveActivityAttributes>) -> String {
        let label = context.state.statusLabel
        return label.count > 12 ? String(label.prefix(12)) : label
    }
}
