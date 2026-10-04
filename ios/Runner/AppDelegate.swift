import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications (iOS setup, README "General setup"): make the app delegate the
    // notification-center delegate so reminders are presented while the app is in the
    // foreground and notification taps reach onDidReceiveNotificationResponse in Dart.
    // FlutterAppDelegate forwards the UNUserNotificationCenterDelegate callbacks to plugins.
    // Must be set before launch finishes. Keep this line in application(_:didFinishLaunching...)
    // when Flutter's tool migrates the app to the UIScene lifecycle (it is app-level, not
    // per-scene).
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
