import Flutter
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

/// "Photos from the Cloud" on an iPhone: one folder chosen in Files (iCloud
/// Drive's, or Google Drive's where its app is installed) and every photo in
/// it and its subfolders, newest first, for the app to show and the user to
/// choose from. Photos are named by their file address ("id") and read only
/// when needed; see photo_pickers.dart.
///
/// "Photos on this device" is the Photos library, which image_picker opens.
final class PhotoPicker: NSObject, UIDocumentPickerDelegate {
  static let channelName = "bills_bay_area/photo_picker"

  /// The photo types the app takes; an iPhone's own are HEIC.
  private static let photoExtensions: Set<String> = [
    "jpg", "jpeg", "png", "webp", "heic", "heif",
  ]

  private var pending: FlutterResult?
  private var limit = 200

  /// The folder last chosen. Files grants access to it, and through it to
  /// the photos inside, only while it is held open.
  private var folder: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pickCloudFolder":
      pickFolder(limit: args["limit"] as? Int ?? 200, result: result)
    case "thumbnail":
      thumbnail(id: args["id"] as? String, size: args["size"] as? Int ?? 240, result: result)
    case "read":
      read(id: args["id"] as? String, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickFolder(limit: Int, result: @escaping FlutterResult) {
    // A picker already open, or nowhere to show one: nothing picked.
    guard pending == nil, let presenter = topViewController() else {
      result(nil)
      return
    }
    pending = result
    self.limit = limit
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let chosen = urls.first else {
      result(nil)
      return
    }
    folder?.stopAccessingSecurityScopedResource()
    folder = chosen.startAccessingSecurityScopedResource() ? chosen : nil
    let limit = limit
    DispatchQueue.global(qos: .userInitiated).async {
      let photos = Self.listPhotos(in: chosen, limit: limit)
      DispatchQueue.main.async { result(photos) }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  private static func listPhotos(in folder: URL, limit: Int) -> [[String: String]] {
    var found: [(url: URL, name: String, modified: Date)] = []
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &error) { url in
      guard
        let items = FileManager.default.enumerator(
          at: url,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: [.skipsPackageDescendants]
        )
      else { return }
      for case let item as URL in items {
        var name = item.lastPathComponent
        var photo = item
        if name.hasPrefix(".") {
          // A photo not yet downloaded from iCloud lists as ".IMG_1.HEIC.icloud";
          // reading it by its real name downloads it.
          guard name.hasSuffix(".icloud") else { continue }
          name = String(name.dropFirst().dropLast(".icloud".count))
          photo = item.deletingLastPathComponent().appendingPathComponent(name)
        }
        guard photoExtensions.contains(photo.pathExtension.lowercased()) else { continue }
        let modified =
          (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
        found.append((photo, name, modified))
      }
    }
    return found.sorted { $0.modified > $1.modified }
      .prefix(limit)
      .map { ["id": $0.url.absoluteString, "name": $0.name] }
  }

  /// A JPEG about [size] pixels across, or nil where Quick Look has none (a
  /// photo still only in iCloud, say).
  private func thumbnail(id: String?, size: Int, result: @escaping FlutterResult) {
    guard let id, let url = URL(string: id) else {
      result(nil)
      return
    }
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: CGSize(width: size, height: size),
      scale: 1,
      representationTypes: .thumbnail
    )
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
      let jpeg = thumbnail?.uiImage.jpegData(compressionQuality: 0.8)
      DispatchQueue.main.async {
        result(jpeg.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  /// The photo in full. The read is coordinated, so a photo still only in
  /// iCloud is downloaded first.
  private func read(id: String?, result: @escaping FlutterResult) {
    guard let id, let url = URL(string: id) else {
      result(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      var data: Data?
      var error: NSError?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) {
        data = try? Data(contentsOf: $0)
      }
      DispatchQueue.main.async {
        if let data {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(FlutterError(code: "picker", message: error?.localizedDescription, details: nil))
        }
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
