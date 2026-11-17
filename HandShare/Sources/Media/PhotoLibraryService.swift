import AVFoundation
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum GalleryFilter: String, CaseIterable, Identifiable {
    case all = "Todo"
    case photos = "Fotos"
    case videos = "Videos"
    case received = "Recibidos"
    case sent = "Enviados"

    var id: String { rawValue }
}

@MainActor
final class PhotoLibraryService: NSObject, ObservableObject {
    static let shared = PhotoLibraryService()

    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var recentAssets: [PHAsset] = []

    private let imageManager = PHCachingImageManager()
    private var isObserverRegistered = false

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    private override init() {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        if isAuthorized {
            registerObserverIfNeeded()
            reloadAssets()
        }
    }

    deinit {
        if isObserverRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func refreshAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAuthorized {
            registerObserverIfNeeded()
            reloadAssets()
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if isAuthorized {
            registerObserverIfNeeded()
            reloadAssets()
        }
        return isAuthorized
    }

    @discardableResult
    func requestAuthorizationOrOpenSettings() async -> Bool {
        refreshAuthorization()
        switch authorizationStatus {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied, .restricted:
            openSystemAppSettings()
            return false
        @unknown default:
            openSystemAppSettings()
            return false
        }
    }

    func reloadAssets() {
        guard isAuthorized else {
            assets = []
            recentAssets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let fetchResult = PHAsset.fetchAssets(with: options)
        var collected: [PHAsset] = []
        collected.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            collected.append(asset)
        }
        self.assets = collected
        self.recentAssets = Array(collected.prefix(24))
    }

    func asset(forIdentifier id: String) -> PHAsset? {
        if let cached = assets.first(where: { $0.localIdentifier == id }) {
            return cached
        }
        let res = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return res.firstObject
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        imageManager.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: opts
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func requestFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            var resumed = false
            imageManager.requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                if resumed { return }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    resumed = true
                    cont.resume(returning: nil)
                    return
                }
                if let data, let img = UIImage(data: data) {
                    resumed = true
                    cont.resume(returning: img)
                    return
                }
                if let err = info?[PHImageErrorKey], err as? NSError != nil {
                    resumed = true
                    cont.resume(returning: nil)
                    return
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    resumed = true
                    cont.resume(returning: nil)
                }
            }
        }
    }

    func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        guard asset.mediaType == .video else { return nil }
        return await withCheckedContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .automatic
            opts.isNetworkAccessAllowed = true
            imageManager.requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                cont.resume(returning: avAsset)
            }
        }
    }

    struct ExportedMedia {
        let fileURL: URL
        let fileName: String
        let mimeType: String
        let sizeBytes: Int64
    }

    func exportAssetToTemporaryFile(_ asset: PHAsset) async -> ExportedMedia? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredResource: PHAssetResource? = if asset.mediaType == .video {
            resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) ?? resources.first
        } else {
            resources.first(where: { $0.type == .fullSizePhoto || $0.type == .photo }) ?? resources.first
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs_export", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        if let res = preferredResource {
            let safeName = LanProtocol.sanitizeFilename(res.originalFilename)
            let outURL = stagingDir.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(safeName)")
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            let ok = await withCheckedContinuation { cont in
                PHAssetResourceManager.default().writeData(for: res, toFile: outURL, options: opts) { err in
                    cont.resume(returning: err == nil)
                }
            }
            if ok, let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path),
               let size = attrs[.size] as? Int64, size > 0 {
                let mime = Self.mimeType(forUTI: res.uniformTypeIdentifier, filename: safeName, isVideo: asset.mediaType == .video)
                let initial = HandShareFileMetadata(fileName: safeName, mimeType: mime, sizeBytes: size, payloadId: 0)
                let corrected = HandShareFileMetadata.corrected(forFileAt: outURL, metadata: initial)
                return ExportedMedia(
                    fileURL: outURL,
                    fileName: corrected.fileName,
                    mimeType: corrected.mimeType,
                    sizeBytes: size
                )
            } else {
                try? FileManager.default.removeItem(at: outURL)
            }
        }

        if asset.mediaType == .image, let image = await requestFullImage(for: asset),
           let jpegData = image.jpegData(compressionQuality: 0.94) {
            let fileName = "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
            let outURL = stagingDir.appendingPathComponent(fileName)
            do {
                try jpegData.write(to: outURL, options: .atomic)
                return ExportedMedia(
                    fileURL: outURL,
                    fileName: fileName,
                    mimeType: "image/jpeg",
                    sizeBytes: Int64(jpegData.count)
                )
            } catch {
                return nil
            }
        }
        return nil
    }

    func saveMediaToPhotosLibrary(fileURL: URL, metadata: HandShareFileMetadata) async -> String? {
        if !isAuthorized {
            let granted = await requestAuthorization()
            if !granted { return nil }
        }
        let corrected = HandShareFileMetadata.corrected(forFileAt: fileURL, metadata: metadata)
        let isVideo = corrected.isVideo

        var createdIdentifier: String?
        let saved: Bool = await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                let req: PHAssetChangeRequest?
                if isVideo {
                    req = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                } else {
                    req = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }
                createdIdentifier = req?.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, _ in
                cont.resume(returning: success)
            })
        }
        if saved {
            reloadAssets()
            return createdIdentifier
        }
        return nil
    }

    private func registerObserverIfNeeded() {
        guard !isObserverRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        isObserverRegistered = true
    }

    private static func mimeType(forUTI uti: String, filename: String, isVideo: Bool) -> String {
        if let type = UTType(uti), let mime = type.preferredMIMEType {
            return mime
        }
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty, let extType = UTType(filenameExtension: ext), let mime = extType.preferredMIMEType {
            return mime
        }
        return isVideo ? "video/mp4" : "image/jpeg"
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.reloadAssets()
        }
    }
}
