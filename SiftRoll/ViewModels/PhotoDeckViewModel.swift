//
//  PhotoDeckViewModel.swift
//  SiftRoll
//
//  Drives the card deck: which photo is on top, what happens on keep / delete,
//  and how external library changes (e.g. deleting in Apple Photos while SiftRoll
//  is open) are reconciled.
//
//  Deletion model
//  --------------
//  PhotoKit shows its own "Allow SiftRoll to delete this photo?" sheet for *every*
//  `performChanges` that deletes, and no app can suppress it. To avoid one system
//  prompt per swipe, swiping left only *queues* the photo (it leaves the deck
//  instantly) and the queue is committed with a single `deleteAssets` call, which
//  triggers exactly one system sheet for the whole batch.
//
//  Our own bilingual "Recently Deleted / 30 days" notice is shown at most once per
//  session, on the first left swipe, and never again for individual photos. Ticking
//  "Remember my setting" (see `DeletionPreferences`) suppresses it across launches.
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

    private static let pendingStorageKey = "SiftRoll.pendingDeletionIdentifiers"

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var keptCount = 0
    /// Photos actually removed from the library (committed batches).
    @Published private(set) var deletedCount = 0
    /// Photos swiped left but not yet committed. Order = swipe order.
    @Published private(set) var pendingDeletions: [PHAsset] = []
    @Published private(set) var isDeleting = false

    /// Bound to the one-time "Before you delete" notice. Whether it is *needed* is
    /// decided by `DeletionPreferences` (session flag + "remember my setting").
    @Published var isShowingDeletionNotice = false
    @Published var activeAlert: DeckAlert?

    private(set) var hasLoaded = false

    private let library: PhotoLibraryService
    private let userDefaults: UserDefaults
    private var fetchResult: PHFetchResult<PHAsset>?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(library: PhotoLibraryService, userDefaults: UserDefaults = .standard) {
        self.library = library
        self.userDefaults = userDefaults
        library.libraryDidChange
            .sink { [weak self] change in self?.apply(change) }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var currentAsset: PHAsset? { asset(at: currentIndex) }
    var nextAsset: PHAsset? { asset(at: currentIndex + 1) }
    var totalCount: Int { assets.count }
    var remainingCount: Int { max(0, assets.count - currentIndex) }
    var pendingCount: Int { pendingDeletions.count }
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

        // Photos queued in a previous session are still in the library; restore the
        // queue so they don't reappear as cards and can still be committed.
        let storedPending = restorePendingQueue()

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let collected = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
                var items: [PHAsset] = []
                items.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in items.append(asset) }
                return items
            }.value

            guard let self, !Task.isCancelled else { return }
            let pendingIDs = Set(storedPending.map(\.localIdentifier))
            self.pendingDeletions = storedPending
            self.assets = collected.filter { !pendingIDs.contains($0.localIdentifier) }
            self.currentIndex = 0
            self.phase = self.assets.isEmpty ? .finished : .browsing
        }
    }

    /// Resets counters and reloads – used by "Start Over" on the finished screen.
    /// The pending queue is kept: those photos are still waiting to be committed.
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

    // MARK: - Delete (queue)

    func presentDeletionNotice() {
        guard currentAsset != nil, !isDeleting else { return }
        isShowingDeletionNotice = true
    }

    func dismissDeletionNotice() {
        isShowingDeletionNotice = false
    }

    /// Moves the top card into the pending queue. No PhotoKit call happens here, so
    /// the card can leave the screen immediately and the next one takes its place.
    func queueCurrentForDeletion() {
        guard let asset = currentAsset else { return }
        pendingDeletions.append(asset)
        persistPendingQueue()
        removeAssets(withIdentifiers: [asset.localIdentifier])
    }

    /// Puts the most recently queued photo back on top of the deck.
    func undoLastQueuedDeletion() {
        guard let asset = pendingDeletions.popLast() else { return }
        persistPendingQueue()
        assets.insert(asset, at: min(currentIndex, assets.count))
        if phase == .finished { phase = .browsing }
    }

    /// Deletes every queued photo in one PhotoKit transaction → one system sheet.
    /// Returns `true` if the batch was removed. Declining the system sheet keeps the
    /// queue intact so the user can commit later.
    func commitPendingDeletions() async -> Bool {
        guard !pendingDeletions.isEmpty, !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }

        let batch = pendingDeletions
        do {
            try await library.delete(batch)
            deletedCount += batch.count
            // Drop only what we sent; anything queued meanwhile stays.
            let sent = Set(batch.map(\.localIdentifier))
            pendingDeletions.removeAll { sent.contains($0.localIdentifier) }
            persistPendingQueue()
            return true
        } catch PhotoLibraryError.cancelled {
            return false
        } catch {
            let detail = (error as? PhotoLibraryError).flatMap(Self.detailMessage) ?? error.localizedDescription
            activeAlert = .deletionFailed(detail: detail)
            return false
        }
    }

    private static func detailMessage(_ error: PhotoLibraryError) -> String? {
        if case .underlying(let inner) = error { return inner.localizedDescription }
        return nil
    }

    // MARK: - Pending queue persistence

    private func persistPendingQueue() {
        userDefaults.set(pendingDeletions.map(\.localIdentifier), forKey: Self.pendingStorageKey)
    }

    private func restorePendingQueue() -> [PHAsset] {
        guard let identifiers = userDefaults.stringArray(forKey: Self.pendingStorageKey),
              !identifiers.isEmpty else { return [] }
        // Preserve swipe order; identifiers whose asset no longer exists are dropped.
        let fetched = library.fetchAssets(withIdentifiers: identifiers)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return identifiers.compactMap { byID[$0] }
    }

    // MARK: - Library change reconciliation

    private func apply(_ change: PHChange) {
        guard let fetchResult,
              let details = change.changeDetails(for: fetchResult) else { return }
        self.fetchResult = details.fetchResultAfterChanges
        guard details.hasIncrementalChanges else { return }

        // Photos removed outside SiftRoll, or by our own committed batch.
        let removed = Set(details.removedObjects.map(\.localIdentifier))
        guard !removed.isEmpty else { return }
        removeAssets(withIdentifiers: removed)

        let pendingBefore = pendingDeletions.count
        pendingDeletions.removeAll { removed.contains($0.localIdentifier) }
        if pendingDeletions.count != pendingBefore { persistPendingQueue() }
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
