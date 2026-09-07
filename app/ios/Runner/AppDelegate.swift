import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Named to match `BookFileStore._platform` on the Dart side.
  private static let bookFilesChannelName = "icanread/book_files"

  /// Held for the life of the app: a `FlutterMethodChannel` that nobody
  /// retains stops answering as soon as it is deallocated.
  private var bookFilesChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Registered through the plugin registry rather than off the root view
    // controller: with a `SceneDelegate` the window is not attached yet at this
    // point, and this runs before the Dart entrypoint either way.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "BookFilesPlugin"
    ) {
      let channel = FlutterMethodChannel(
        name: AppDelegate.bookFilesChannelName,
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        AppDelegate.handleBookFilesCall(call, result)
      }
      bookFilesChannel = channel
    }
  }

  /// Marks a directory as excluded from iCloud and iTunes backups.
  ///
  /// The books directory holds the reader's imported PDFs, which must never
  /// leave the device. The flag is inherited by files created inside the
  /// directory afterwards, so it is set once on the directory itself.
  private static func handleBookFilesCall(
    _ call: FlutterMethodCall,
    _ result: FlutterResult
  ) {
    guard call.method == "excludeFromBackup" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let path = call.arguments as? String else {
      result(
        FlutterError(
          code: "bad_argument",
          message: "excludeFromBackup expects a file path as its argument",
          details: nil
        )
      )
      return
    }

    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "exclude_failed",
          message: error.localizedDescription,
          details: path
        )
      )
    }
  }
}
