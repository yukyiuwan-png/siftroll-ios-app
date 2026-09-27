//
//  PhotoLibraryService.swift
//  SiftRoll
//
//  The only place that talks to PhotoKit. Photos are never imported or copied:
//  we fetch `PHAsset` metadata, request a preview image on demand, and delete
//  through `PHAssetChangeRequest` so items land in the system "Recently Deleted"
//  album exactly like Apple Photos.
//

import Photos
import UIKit
import Combine

/// App-level view of `PHAuthorizationStatus` for the `.readWrite` access level.
enum PhotoAuthorization: Equatable {
    case notDetermined
    /// Full read/write access – the only state in which SiftRoll can browse and delete.
    case full
    /// User picked "Limit Access" / "Select Photos…" – not sufficient for cleanup.
    case limited
    case denied
    case restricted

    var allowsBrowsing: Bool { self == .full }
}

/// Errors surfaced to the UI. Messages are localized in the views via keys.
enum PhotoLibraryError: Error {
    /// PhotoKit returned no image and no more specific reason.
    case imageUnavailable
    /// The full-size asset lives in iCloud and has not been downloaded yet.
    case assetInCloud
    /// The user cancelled (e.g. dismissed the system delete dialog) – not an error to show.
    case cancelled
    /// Wrapped PhotoKit error.
    case underlying(Error)
}

@MainActor
final class PhotoLibraryService: NSObject, ObservableObject {
    /// Current permission state. Refreshed on launch, after requests, and when
    /// the app returns from Settings.
    @Published private(set) var authorization: PhotoAuthorization

    /// Fires whenever the system library changes (deletions, new photos, iCloud sync).
    let libraryDidChange = PassthroughSubject<PHChange, Never>()

    private let imageLoader = PhotoImageLoader()

    override init() {
        authorization = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Authorization

    /// Shows the system permission dialog (Full Access / Limit Access / Don't Allow).
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorization = Self.map(status)
    }

    /// Re-reads the status without prompting – call when returning from Settings.
    func refreshAuthorization() {
        authorization = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAuthorization {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: - Fetching

    /// All still images in the library, newest first. Videos are intentionally excluded.
    func fetchAllPhotos() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    // MARK: - Image loading

    /// Pixel size to request for a card of `pointSize`. We ask for 1.5× the on-screen
    /// size so pinch-to-zoom stays sharp, capped to keep memory reasonable.
    static func targetPixelSize(for pointSize: CGSize, displayScale: CGFloat) -> CGSize {
        let maxDimension: CGFloat = 2400
        let width = min(pointSize.width * displayScale * 1.5, maxDimension)
        let height = min(pointSize.height * displayScale * 1.5, maxDimension)
        return CGSize(width: width, height: height)
    }

    /// Warm the cache for upcoming cards so the next swipe feels instant.
    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        imageLoader.prefetch(assets, targetSize: targetSize)
    }

    /// Loads a preview image for `asset`, honoring Swift task cancellation.
    func loadImage(for asset: PHAsset, targetSize: CGSize) async throws -> UIImage {
        try await imageLoader.loadImage(for: asset, targetSize: targetSize)
    }

    // MARK: - Deletion

    /// Assets for the given local identifiers (used to restore the pending queue).
    func fetchAssets(withIdentifiers identifiers: [String]) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
    }

    /// Moves `assets` to "Recently Deleted" in a single transaction. iOS shows one
    /// confirmation sheet per `performChanges` call regardless of how many assets it
    /// contains, so batching here is what keeps the prompt count down. Dismissing the
    /// sheet surfaces as `PhotoLibraryError.cancelled`.
    func delete(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            throw PhotoLibraryError.cancelled
        } catch {
            throw PhotoLibraryError.underlying(error)
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    /// Called on an arbitrary background queue; hop to the main actor before publishing.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.libraryDidChange.send(changeInstance)
        }
    }
}

// MARK: - Image loader

/// Wraps `PHCachingImageManager`. Deliberately *not* main-actor isolated: PhotoKit
/// invokes result handlers on a background queue, and this keeps the async bridge
/// free of any actor assumptions.
final class PhotoImageLoader: @unchecked Sendable {
    private let manager = PHCachingImageManager()

    private static func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        // Single high-quality delivery keeps the async API simple (handler fires once).
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true   // allow iCloud download when needed
        options.isSynchronous = false
        return options
    }

    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        manager.stopCachingImagesForAllAssets()
        guard !assets.isEmpty else { return }
        manager.startCachingImages(for: assets,
                                   targetSize: targetSize,
                                   contentMode: .aspectFit,
                                   options: Self.requestOptions())
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async throws -> UIImage {
        let manager = self.manager
        let token = ImageRequestToken()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                let requestID = manager.requestImage(for: asset,
                                                     targetSize: targetSize,
                                                     contentMode: .aspectFit,
                                                     options: Self.requestOptions()) { image, info in
                    // Guard against any double invocation from PhotoKit.
                    guard token.claimResume() else { return }

                    if let image {
                        continuation.resume(returning: image)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: PhotoLibraryError.cancelled)
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: PhotoLibraryError.underlying(error))
                    } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                        continuation.resume(throwing: PhotoLibraryError.assetInCloud)
                    } else {
                        continuation.resume(throwing: PhotoLibraryError.imageUnavailable)
                    }
                }
                token.register(requestID, manager: manager)
            }
        } onCancel: {
            token.cancel(manager: manager)
        }
    }
}

/// Thread-safe bookkeeping for a single `PHImageManager` request so it can be
/// cancelled from Swift concurrency and never resumes its continuation twice.
private final class ImageRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false
    private var isResumed = false

    func register(_ id: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        requestID = id
        let cancelNow = isCancelled
        lock.unlock()
        if cancelNow { manager.cancelImageRequest(id) }
    }

    func cancel(manager: PHImageManager) {
        lock.lock()
        isCancelled = true
        let id = requestID
        lock.unlock()
        if let id { manager.cancelImageRequest(id) }
    }

    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isResumed { return false }
        isResumed = true
        return true
    }
}
