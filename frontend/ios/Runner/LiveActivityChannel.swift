import UIKit
import Flutter
import ActivityKit

class LiveActivityChannel: NSObject {
    private static let methodChannelName = "com.wiz.wizuserapp/live_activity"
    private static let eventChannelName = "com.wiz.wizuserapp/live_activity_token"

    private var tokenSink: FlutterEventSink?
    private var tokenUpdateTask: Task<Void, Never>?

    static let shared = LiveActivityChannel()

    func register(with controller: FlutterViewController) {
        let methodChannel = FlutterMethodChannel(
            name: LiveActivityChannel.methodChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        methodChannel.setMethodCallHandler(handleMethodCall)

        let eventChannel = FlutterEventChannel(
            name: LiveActivityChannel.eventChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        eventChannel.setStreamHandler(self)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startOrderLiveActivity":
            startOrderLiveActivity(args: call.arguments as? [String: Any], result: result)
        case "updateOrderLiveActivity":
            updateOrderLiveActivity(args: call.arguments as? [String: Any], result: result)
        case "endOrderLiveActivity":
            endOrderLiveActivity(args: call.arguments as? [String: Any], result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startOrderLiveActivity(args: [String: Any]?, result: @escaping FlutterResult) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "NOT_ENABLED", message: "Live Activities are not enabled", details: nil))
            return
        }
        guard let args = args,
              let orderId = args["orderId"] as? String,
              let status = args["status"] as? String,
              let statusLabel = args["statusLabel"] as? String,
              let storeName = args["storeName"] as? String,
              let orderNumber = args["orderNumber"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        let attributes = OrderLiveActivityAttributes(orderId: orderId)
        let contentState = OrderLiveActivityAttributes.ContentState(
            status: status,
            statusLabel: statusLabel,
            storeName: storeName,
            orderNumber: orderNumber,
            etaText: args["etaText"] as? String ?? "",
            progress: (args["progress"] as? Double) ?? 0.0
        )

        // If an activity already exists for this order (e.g. app restarted), reuse it.
        if let existing = Activity<OrderLiveActivityAttributes>.activities.first(where: { $0.attributes.orderId == orderId }) {
            Task {
                await existing.update(using: contentState)
            }
            observeTokenUpdates(activity: existing)
            result(["activityId": existing.id])
            return
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: .token
            )
            observeTokenUpdates(activity: activity)
            result(["activityId": activity.id])
        } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    /// Re-attach token observation to any still-running activities (called at app launch).
    func resumeExistingActivities() {
        for activity in Activity<OrderLiveActivityAttributes>.activities {
            observeTokenUpdates(activity: activity)
        }
    }

    private func updateOrderLiveActivity(args: [String: Any]?, result: @escaping FlutterResult) {
        guard let args = args,
              let orderId = args["orderId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing orderId", details: nil))
            return
        }
        Task {
            for activity in Activity<OrderLiveActivityAttributes>.activities where activity.attributes.orderId == orderId {
                let contentState = OrderLiveActivityAttributes.ContentState(
                    status: args["status"] as? String ?? activity.state.status,
                    statusLabel: args["statusLabel"] as? String ?? activity.state.statusLabel,
                    storeName: args["storeName"] as? String ?? activity.state.storeName,
                    orderNumber: args["orderNumber"] as? String ?? activity.state.orderNumber,
                    etaText: args["etaText"] as? String ?? activity.state.etaText,
                    progress: (args["progress"] as? Double) ?? activity.state.progress
                )
                await activity.update(using: contentState)
            }
            result(nil)
        }
    }

    private func endOrderLiveActivity(args: [String: Any]?, result: @escaping FlutterResult) {
        guard let orderId = args?["orderId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing orderId", details: nil))
            return
        }
        Task {
            for activity in Activity<OrderLiveActivityAttributes>.activities where activity.attributes.orderId == orderId {
                await activity.end(nil, dismissalPolicy: .default)
            }
            result(nil)
        }
    }

    private func observeTokenUpdates(activity: Activity<OrderLiveActivityAttributes>) {
        tokenUpdateTask?.cancel()
        tokenUpdateTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                tokenSink?(token)
            }
        }
    }
}

extension LiveActivityChannel: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        tokenSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        tokenSink = nil
        tokenUpdateTask?.cancel()
        return nil
    }
}
