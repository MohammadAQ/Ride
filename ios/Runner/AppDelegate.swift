import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.example.carpal_app/phone_launcher"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let methodChannel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )

      methodChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "openDialer":
          guard
            let arguments = call.arguments as? [String: Any],
            let rawNumber = arguments["phoneNumber"] as? String
          else {
            result(false)
            return
          }

          let phoneNumber = rawNumber.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !phoneNumber.isEmpty,
            let url = URL(string: "tel://\(phoneNumber)"),
            UIApplication.shared.canOpenURL(url)
          else {
            result(false)
            return
          }

          DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            result(true)
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
