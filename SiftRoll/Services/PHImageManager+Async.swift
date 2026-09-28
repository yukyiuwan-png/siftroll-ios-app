//
//  PHImageManager+Async.swift
//
//  Bridges PhotoKit's callback-based `requestImage` to async/await without blocking
//  any executor. Never sets `isSynchronous`; ignores degraded previews and resumes
//  exactly once when the final image (or an error) arrives.
//

import Photos
import UIKit

extension PHImageManager {
    /// Async wrapper around `requestImage(for:targetSize:contentMode:options:resultHandler:)`.
    /// Safe to call from Swift concurrency contexts (including when awaited off the main actor).
    func requestImageAsync(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        options: PHImageRequestOptions? = nil
    ) async throws -> UIImage {
        let opts = options ?? Self.defaultAsyncOptions()
        precondition(!opts.isSynchronous, "Synchronous PhotoKit image requests must not be used with async/await")

        let state = RequestState()
        let manager = self

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                state.store(continuation: continuation)
                let requestID = requestImage(for: asset,
                                               targetSize: targetSize,
                                               contentMode: contentMode,
                                               options: opts) { image, info in
                    state.deliver(image: image, info: info)
                }
                state.register(requestID: requestID, cancelWith: manager)
            }
        } onCancel: {
            state.cancel(using: manager)
        }
    }

    private static func defaultAsyncOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }
}

// MARK: - One-shot continuation (PhotoKit may call the handler more than once)

private final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private(set) var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var didResume = false

    func store(continuation: CheckedContinuation<UIImage, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func register(requestID: PHImageRequestID, cancelWith manager: PHImageManager) {
        lock.lock()
        self.requestID = requestID
        let cancelNow = didResume
        lock.unlock()
        if cancelNow { manager.cancelImageRequest(requestID) }
    }

    func cancel(using manager: PHImageManager) {
        lock.lock()
        let id = requestID
        lock.unlock()
        guard id != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(id)
    }

    func deliver(image: UIImage?, info: [AnyHashable: Any]?) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }

        if (info?[PHImageCancelledKey] as? Bool) == true {
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: PhotoLibraryError.cancelled)
            return
        }

        if let error = info?[PHImageErrorKey] as? Error {
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: PhotoLibraryError.underlying(error))
            return
        }

        // Opportunistic / progressive delivery: wait for the non-degraded frame.
        if (info?[PHImageResultIsDegradedKey] as? Bool) == true {
            lock.unlock()
            return
        }

        if let image {
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: image)
            return
        }

        if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: PhotoLibraryError.assetInCloud)
            return
        }

        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: PhotoLibraryError.imageUnavailable)
    }
}
