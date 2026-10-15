import ActivityKit

struct OrderLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = ContentState

    public struct ContentState: Codable, Hashable {
        var status: String
        var statusLabel: String
        var storeName: String
        var orderNumber: String
        var etaText: String
        var progress: Double
    }

    var orderId: String
}
