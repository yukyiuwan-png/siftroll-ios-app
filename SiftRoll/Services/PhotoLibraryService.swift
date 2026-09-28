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

    /// Image requests run on a dedicated actor so PhotoKit callbacks never force a
    /// synchronous hop on the main actor (the source of `unsafeForcedSync` warnings).
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

    /// Warm the cache for upcoming cards so the next swipe feels instant (non-blocking).
    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        Task { await imageLoader.prefetch(assets, targetSize: targetSize) }
    }

    /// Loads a preview image for `asset`. Suspends the caller without blocking its
    /// executor; work runs on `PhotoImageLoader`'s actor.
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

/// Owns the caching manager and performs all PhotoKit image work off the main actor.
actor PhotoImageLoader {
    private let manager = PHCachingImageManager()

    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        manager.stopCachingImagesForAllAssets()
        guard !assets.isEmpty else { return }
        manager.startCachingImages(for: assets,
                                   targetSize: targetSize,
                                   contentMode: .aspectFit,
                                   options: Self.requestOptions())
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async throws -> UIImage {
        try await manager.requestImageAsync(for: asset,
                                            targetSize: targetSize,
                                            contentMode: .aspectFit,
                                            options: Self.requestOptions())
    }

    private static func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }
}
