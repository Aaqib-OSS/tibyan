import AVFoundation
import Cocoa
import CoreLocation
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // «المزامنة» through the reader's iCloud.
    ICloudSyncChannel.attach(flutterViewController.engine.binaryMessenger)
    VideoEncoderChannel.attach(flutterViewController.engine.binaryMessenger)
    // «مواقيت الصلاة»: one coarse position, the full adhan, the login item.
    PrayerChannel.attach(flutterViewController.engine.binaryMessenger)
    // «المسبحة»: the bead sounds (no volume keys, widget or watch here).
    TasbihSoundChannel.attach(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Hidden until Dart has restored the last size and place
  // (lib/core/ui/desktop_window.dart), so the window does not jump.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// «المزامنة» on Apple devices (`app.tibyan/icloud`, lib/core/sync/cloud/
/// icloud_store.dart): each device's sync file in the `Sync` folder of the
/// app's iCloud container, which the reader does not see in iCloud Drive.
/// A build without the iCloud capability has no container and says
/// `notInBuild`. Files not yet downloaded are asked for and read at a
/// later sync. Work runs off the main thread.
enum ICloudSyncChannel {
  static let containerId = "iCloud.app.tibyan.tibyan"
  private static let queue = DispatchQueue(label: "app.tibyan.icloud", qos: .utility)
  private static var channel: FlutterMethodChannel?

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "app.tibyan/icloud", binaryMessenger: messenger)
    c.setMethodCallHandler { call, result in
      queue.async {
        let reply: Any?
        do {
          reply = try handle(call)
        } catch {
          reply = FlutterError(code: "icloud", message: error.localizedDescription, details: nil)
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
    channel = c
  }

  private static func folder() -> URL? {
    guard FileManager.default.ubiquityIdentityToken != nil,
      let root = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else { return nil }
    let dir = root.appendingPathComponent("Sync", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func handle(_ call: FlutterMethodCall) throws -> Any? {
    switch call.method {
    case "status":
      if FileManager.default.ubiquityIdentityToken == nil { return "noAccount" }
      return folder() == nil ? "notInBuild" : "available"
    case "readAll":
      guard let dir = folder() else { throw SyncError.unavailable }
      var out: [String: String] = [:]
      let items = try FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
      for url in items {
        let name = url.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          // Not downloaded yet: asked for now, read at a later sync.
          let real = String(name.dropFirst().dropLast(".icloud".count))
          try? FileManager.default.startDownloadingUbiquitousItem(
            at: dir.appendingPathComponent(real))
          continue
        }
        guard name.hasPrefix("tibyan-sync-"), name.hasSuffix(".json") else { continue }
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
          .ubiquitousItemDownloadingStatus
        if status != nil, status != .current {
          try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        if let text = coordinatedRead(url) { out[name] = text }
      }
      return out
    case "write":
      guard let dir = folder() else { throw SyncError.unavailable }
      guard let args = call.arguments as? [String: Any],
        let name = args["name"] as? String, let content = args["content"] as? String,
        name.hasPrefix("tibyan-sync-"), !name.contains("/")
      else { throw SyncError.badArguments }
      let url = dir.appendingPathComponent(name)
      var coordError: NSError?
      var writeError: Error?
      NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: url, options: .forReplacing, error: &coordError
      ) { target in
        do { try Data(content.utf8).write(to: target, options: .atomic) } catch {
          writeError = error
        }
      }
      if let e = coordError ?? writeError { throw e }
      return nil
    case "deleteAll":
      guard let dir = folder() else { throw SyncError.unavailable }
      let items = try FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil)
      for url in items {
        var coordError: NSError?
        var removeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
          writingItemAt: url, options: .forDeleting, error: &coordError
        ) { target in
          do { try FileManager.default.removeItem(at: target) } catch { removeError = error }
        }
        if let e = coordError ?? removeError { throw e }
      }
      return nil
    default:
      return FlutterMethodNotImplemented
    }
  }

  private static func coordinatedRead(_ url: URL) -> String? {
    var text: String?
    var coordError: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: [], error: &coordError
    ) { target in
      text = try? String(contentsOf: target, encoding: .utf8)
    }
    return text
  }

  enum SyncError: LocalizedError {
    case unavailable, badArguments
    var errorDescription: String? {
      switch self {
      case .unavailable: return "iCloud is not available"
      case .badArguments: return "bad arguments"
      }
    }
  }
}

/// «مواقيت الصلاة»'s channel (`app.tibyan/prayer`): one coarse position
/// for «حدّد موقعي» (when in use, reduced accuracy, a single fix; never
/// tracked), and the full adhan played in the app when the reader taps the
/// alert or the app is in front. The alert itself is a plain scheduled
/// notification whose sound is the short cut in Library/Sounds.
final class PrayerChannel: NSObject, CLLocationManagerDelegate {
  private static var shared: PrayerChannel?
  private let channel: FlutterMethodChannel
  private var manager: CLLocationManager?
  private var pending: FlutterResult?
  private var player: AVQueuePlayer?
  private var endObserver: NSObjectProtocol?

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "app.tibyan/prayer", binaryMessenger: messenger)
    let me = PrayerChannel(channel: c)
    c.setMethodCallHandler { call, result in me.handle(call, result) }
    shared = me
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "locate":
      locate(result)
    case "play":
      play((args?["files"] as? [String]) ?? [], volume: Float(args?["volume"] as? Double ?? 0.7))
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "loginItem":
      result(PrayerChannel.loginItem(args?["on"] as? Bool ?? false))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Location

  private func locate(_ result: @escaping FlutterResult) {
    pending?(nil)
    pending = result
    let m = manager ?? CLLocationManager()
    manager = m
    m.delegate = self
    m.desiredAccuracy = kCLLocationAccuracyReduced
    switch m.authorizationStatus {
    case .notDetermined:
      m.requestWhenInUseAuthorization()
    case .denied, .restricted:
      finish(nil)
    default:
      m.requestLocation()
    }
  }

  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
    guard pending != nil else { return }
    switch m.authorizationStatus {
    case .notDetermined: return
    case .denied, .restricted: finish(nil)
    default: m.requestLocation()
    }
  }

  func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    finish(locations.last)
  }

  func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
    finish(nil)
  }

  private func finish(_ l: CLLocation?) {
    let r = pending
    pending = nil
    guard let r = r else { return }
    if let l = l {
      r(["lat": l.coordinate.latitude, "lon": l.coordinate.longitude])
    } else {
      r(nil)
    }
  }

  // MARK: The adhan in the app

  /// In-app only: the player's own volume (alerts follow the system's).
  private func play(_ files: [String], volume: Float) {
    stop()
    let items = files.compactMap { f -> AVPlayerItem? in
      let url = f.hasPrefix("http") ? URL(string: f) : URL(fileURLWithPath: f)
      return url.map { AVPlayerItem(url: $0) }
    }
    guard let last = items.last else { return }
    let p = AVQueuePlayer(items: items)
    p.volume = max(0, min(1, volume))
    player = p
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: last, queue: .main
    ) { [weak self] _ in self?.stop() }
    p.play()
    channel.invokeMethod("playing", arguments: true)
  }

  private func stop() {
    if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    endObserver = nil
    if player != nil {
      player?.pause()
      player = nil
      channel.invokeMethod("playing", arguments: false)
    }
  }

  /// Opens the app at login (SMAppService, macOS 13+): asked when prayer
  /// times are switched on, so the full adhan can play.
  static func loginItem(_ on: Bool) -> Bool {
    guard #available(macOS 13.0, *) else { return false }
    do {
      if on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return true
    } catch {
      return false
    }
  }
}

/// «المسبحة»'s sounds on the Mac (`app.tibyan/tasbih`): the bundled bead
/// knocks and the click, as on iOS. AVAudioPlayer on macOS has no shared
/// audio session, so the recitation is never interrupted.
final class TasbihSoundChannel {
  private static var shared: TasbihSoundChannel?
  /// A few players of each sound, by its asset, so quick counts overlap.
  private var players: [String: [AVAudioPlayer]] = [:]
  private var next = 0
  private static let clickAsset = "assets/tasbih/click.wav"

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "app.tibyan/tasbih", binaryMessenger: messenger)
    let me = TasbihSoundChannel()
    c.setMethodCallHandler { call, result in me.handle(call, result) }
    shared = me
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    switch call.method {
    case "click":
      play(TasbihSoundChannel.clickAsset)
      result(nil)
    case "play":
      if let asset = call.arguments as? String { play(asset) }
      result(nil)
    case "preload":
      for asset in (call.arguments as? [String]) ?? [] { _ = load(asset) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The players of a bundled sound, made (and readied) on first use.
  private func load(_ asset: String) -> [AVAudioPlayer] {
    if let ready = players[asset] { return ready }
    guard asset.hasPrefix("assets/tasbih/"), !asset.contains(".."),
      let frameworks = Bundle.main.privateFrameworksURL
    else { return [] }
    let url = frameworks.appendingPathComponent("App.framework/Resources/flutter_assets/\(asset)")
    let made = (0..<(asset == TasbihSoundChannel.clickAsset ? 3 : 2)).compactMap { _ in
      try? AVAudioPlayer(contentsOf: url)
    }
    made.forEach { $0.prepareToPlay() }
    players[asset] = made
    return made
  }

  private func play(_ asset: String) {
    let ready = load(asset)
    guard !ready.isEmpty else { return }
    let p = ready[next % ready.count]
    next += 1
    p.currentTime = 0
    p.play()
    #if DEBUG
      NSLog("TibyanTasbih: played %@", asset)
    #endif
  }
}
