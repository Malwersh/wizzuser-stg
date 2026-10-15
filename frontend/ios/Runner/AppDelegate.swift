import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Use a dedicated Google Maps SDK key (Maps SDK for iOS enabled) rather than
    // the Firebase API key in GoogleService-Info.plist. The Firebase key does not
    // have Maps SDK for iOS enabled, which caused blank/white map tiles.
    GMSServices.provideAPIKey("AIzaSyDrvzgil3g2SwE8zl_44IGM35n7khAyoVI")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
