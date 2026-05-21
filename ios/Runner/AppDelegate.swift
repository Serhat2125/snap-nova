import Flutter
import UIKit
import UserNotifications

// AppDelegate — Flutter + FCM push + Universal Link entry point.
//
// FirebaseAppDelegateProxyEnabled=true (Info.plist) sayesinde FCM kendini
// otomatik bağlar; biz sadece notification authorization isteme + UNUserNotification
// center delegate'i set ediyoruz. Universal Link açma flutter app_links plugin'i
// tarafından otomatik handle edilir (continueUserActivity).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 10+ bildirim authorization isteği — Flutter tarafı da requestPermission
    // çağırır ama burada da set'liyoruz ki APNs token'ı erkenden gelsin.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
