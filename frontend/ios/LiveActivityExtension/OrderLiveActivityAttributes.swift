import ActivityKit

@available(iOS 16.1, *)
struct OrderLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var statusLabel: String
        var storeName: String
        var orderNumber: String
        var etaText: String
        var progress: Double
        var arrivalEarliestEpoch: Double?
        var arrivalLatestEpoch: Double?
    }

    var orderId: String
}
