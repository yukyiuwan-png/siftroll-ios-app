//
//  PhotoDeckViewModel.swift
//  SiftRoll
//
//  Drives the card deck: which photo is on top, what happens on keep / delete,
//  and how external library changes (e.g. deleting in Apple Photos while SiftRoll
//  is open) are reconciled.
//

import Photos
import Combine
import SwiftUI

@MainActor
final class PhotoDeckViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case browsing
        case finished
    }

    /// Non-blocking error alerts shown over the deck.
    enum DeckAlert: Identifiable {
        case deletionFailed(detail: String)

        var id: String {
            switch self {
            case .deletionFailed(let detail): return "deletionFailed-\(detail)"
            }
        }
    }

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var keptCount = 0
    @Published private(set) var deletedCount = 0
    @Published private(set) var isDeleting = false

    /// Bound to the delete confirmation alert.
    @Published var isConfirmingDeletion = false
    @Published var activeAlert: DeckAlert?

    private(set) var hasLoaded = false

    private let library: PhotoLibraryService
    private var fetchResult: PHFetchResult<PHAsset>?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Assets we deleted ourselves and are still animating off-screen. The change
    /// observer must not remove them early or the card would vanish mid-flight.
    private var deletionsInFlight = Set<String>()

    init(library: PhotoLibraryService) {
        self.library = library
        library.libraryDidChange
            .sink { [weak self] change in self?.apply(change) }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var currentAsset: PHAsset? { asset(at: currentIndex) }
    var nextAsset: PHAsset? { asset(at: currentIndex + 1) }
    var totalCount: Int { assets.count }
    var remainingCount: Int { max(0, assets.count - currentIndex) }
    /// 1-based position for the "12 of 3,204" label.
    var displayPosition: Int { min(currentIndex + 1, max(assets.count, 1)) }

    /// Next few assets to pre-cache.
    func upcomingAssets(limit: Int = 3) -> [PHAsset] {
        let start = currentIndex + 1
        guard start < assets.count else { return [] }
        return Array(assets[start..<min(start + limit, assets.count)])
    }

    private func asset(at index: Int) -> PHAsset? {
        assets.indices.contains(index) ? assets[index] : nil
    }

    // MARK: - Loading

    /// Fetches every image in the library. Enumerating a `PHFetchResult` touches each
    /// asset, so it runs off the main thread for large libraries.
    func loadLibrary() {
        hasLoaded = true
        phase = .loading
        let result = library.fetchAllPhotos()
        fetchResult = result

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let collected = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
                var items: [PHAsset] = []
                items.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in items.append(asset) }
                return items
            }.value

            guard let self, !Task.isCancelled else { return }
            self.assets = collected
            self.currentIndex = 0
            self.phase = collected.isEmpty ? .finished : .browsing
        }
    }

    /// Resets counters and reloads – used by "Start Over" on the finished screen.
    func restart() {
        keptCount = 0
        deletedCount = 0
        loadLibrary()
    }

    // MARK: - Keep / skip

    func keepCurrent() {
        guard currentAsset != nil else { return }
        keptCount += 1
        advance()
    }

    /// Used when a photo cannot be loaded and the user chooses to move on.
    func skipCurrent() {
        guard currentAsset != nil else { return }
        advance()
    }

    private func advance() {
        currentIndex += 1
        if currentIndex >= assets.count {
            phase = .finished
        }
    }

    // MARK: - Delete

    func requestDeletion() {
        guard currentAsset != nil, !isDeleting else { return }
        isConfirmingDeletion = true
    }

    /// Performs the deletion after the user confirmed. Returns `true` on success.
    /// The asset stays in `assets` until `finalizeDeletion(of:)` so the view can
    /// animate the card away first.
    func confirmDeletion() async -> Bool {
        guard let asset = currentAsset else { return false }
        isDeleting = true
        defer { isDeleting = false }

        deletionsInFlight.insert(asset.localIdentifier)
        do {
            try await library.delete(asset)
            deletedCount += 1
            return true
        } catch PhotoLibraryError.cancelled {
            deletionsInFlight.remove(asset.localIdentifier)
            return false
        } catch {
            deletionsInFlight.remove(asset.localIdentifier)
            let detail = (error as? PhotoLibraryError).flatMap(Self.detailMessage) ?? error.localizedDescription
            activeAlert = .deletionFailed(detail: detail)
            return false
        }
    }

    /// Removes the deleted asset from the deck once its fly-away animation finished.
    func finalizeDeletion(of asset: PHAsset) {
        deletionsInFlight.remove(asset.localIdentifier)
        removeAssets(withIdentifiers: [asset.localIdentifier])
    }

    private static func detailMessage(_ error: PhotoLibraryError) -> String? {
        if case .underlying(let inner) = error { return inner.localizedDescription }
        return nil
    }

    // MARK: - Library change reconciliation

    private func apply(_ change: PHChange) {
        guard let fetchResult,
              let details = change.changeDetails(for: fetchResult) else { return }
        self.fetchResult = details.fetchResultAfterChanges
        guard details.hasIncrementalChanges else { return }

        // Photos removed outside SiftRoll (or by us, once the animation is done).
        var removed = Set(details.removedObjects.map(\.localIdentifier))
        removed.subtract(deletionsInFlight)
        removeAssets(withIdentifiers: removed)
        // New photos are deliberately not injected mid-session; "Start Over" picks them up.
    }

    private func removeAssets(withIdentifiers identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        var removedBeforeCursor = 0
        var remaining: [PHAsset] = []
        remaining.reserveCapacity(assets.count)

        for (index, asset) in assets.enumerated() {
            if identifiers.contains(asset.localIdentifier) {
                if index < currentIndex { removedBeforeCursor += 1 }
            } else {
                remaining.append(asset)
            }
        }

        assets = remaining
        currentIndex = max(0, min(currentIndex - removedBeforeCursor, remaining.count))
        if phase == .browsing, currentIndex >= remaining.count {
            phase = .finished
        }
    }
}
