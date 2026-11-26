import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var activityLinkChannel: FlutterMethodChannel?
  private var pendingActivityLink: String?

  private func receiveActivityLink(_ url: URL) -> Bool {
    guard url.scheme == "wizuser", url.host == "orders", url.pathComponents.count == 2,
          url.query == nil, url.fragment == nil else { return false }
    pendingActivityLink = url.absoluteString
    activityLinkChannel?.invokeMethod("openOrderTracking", arguments: url.absoluteString)
    return true
  }

  override func application(_ app: UIApplication, open url: URL,
      options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if receiveActivityLink(url) { return true }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Use a dedicated Google Maps SDK key (Maps SDK for iOS enabled) rather than
    // the Firebase API key in GoogleService-Info.plist. The Firebase key does not
    // have Maps SDK for iOS enabled, which caused blank/white map tiles.
    GMSServices.provideAPIKey("AIzaSyDrvzgil3g2SwE8zl_44IGM35n7khAyoVI")

    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if #available(iOS 16.1, *), let controller = window?.rootViewController as? FlutterViewController {
      LiveActivityChannel.shared.register(with: controller)
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.wiz.wizuserapp/activity_link", binaryMessenger: controller.binaryMessenger)
      activityLinkChannel = channel
      channel.setMethodCallHandler { [weak self] call, reply in
        if call.method == "pendingOrderLink" {
          reply(self?.pendingActivityLink)
          self?.pendingActivityLink = nil
        } else { reply(FlutterMethodNotImplemented) }
      }
    }
    if let url = launchOptions?[.url] as? URL { _ = receiveActivityLink(url) }
    return result
  }
}
