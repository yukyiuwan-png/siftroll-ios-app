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
    private static let selectionStorageKey = "SiftRoll.selectedAlbum"

    /// Every photo in the library (minus the pending queue), newest first.
    @Published private(set) var allAssets: [PHAsset] = []
    /// The deck: `allAssets` filtered to `selectedAlbum`.
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var currentIndex = 0 {
        didSet { progressByAlbum[selectedAlbum] = currentIndex }
    }
    @Published private(set) var phase: Phase = .loading

    /// Automatic year → month albums, newest first, with live counts.
    @Published private(set) var yearAlbums: [YearAlbum] = []
    @Published private(set) var selectedAlbum: AlbumSelection = .all

    /// Creation-date key per asset identifier (missing = undated).
    private var dateKeys: [String: DateKey] = [:]
    /// Where the user left off in each album, so switching back resumes.
    private var progressByAlbum: [AlbumSelection: Int] = [:]
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
        if let data = userDefaults.data(forKey: Self.selectionStorageKey),
           let stored = try? JSONDecoder().decode(AlbumSelection.self, from: data) {
            selectedAlbum = stored
        }
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
    var libraryCount: Int { allAssets.count }
    /// 1-based position for the "12 of 3,204" label.
    var displayPosition: Int { min(currentIndex + 1, max(assets.count, 1)) }
    /// True when the deck is filtered to a year or month rather than the whole library.
    var isViewingAlbum: Bool { selectedAlbum != .all }

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
            // Enumerate and bucket by year/month off the main thread.
            let (collected, keys) = await Task.detached(priority: .userInitiated) { () -> ([PHAsset], [String: DateKey]) in
                let calendar = Calendar.current
                var items: [PHAsset] = []
                var keys: [String: DateKey] = [:]
                items.reserveCapacity(result.count)
                keys.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in
                    items.append(asset)
                    if let key = Self.dateKey(for: asset, calendar: calendar) {
                        keys[asset.localIdentifier] = key
                    }
                }
                return (items, keys)
            }.value

            guard let self, !Task.isCancelled else { return }
            let pendingIDs = Set(storedPending.map(\.localIdentifier))
            self.pendingDeletions = storedPending
            self.dateKeys = keys
            self.allAssets = collected.filter { !pendingIDs.contains($0.localIdentifier) }
            self.rebuildAlbums()

            // A remembered album may no longer exist (all its photos deleted).
            if !self.albumExists(self.selectedAlbum) { self.selectedAlbum = .all }
            self.progressByAlbum.removeAll()
            self.applySelection()
        }
    }

    /// Resets counters and reloads – used by "Start Over" on the finished screen.
    /// The pending queue is kept: those photos are still waiting to be committed.
    func restart() {
        keptCount = 0
        deletedCount = 0
        loadLibrary()
    }

    nonisolated private static func dateKey(for asset: PHAsset, calendar: Calendar) -> DateKey? {
        guard let date = asset.creationDate else { return nil }
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        return DateKey(year: year, month: month)
    }

    // MARK: - Albums

    /// Switches the deck to another automatic album, resuming where it was left off.
    func selectAlbum(_ selection: AlbumSelection) {
        guard selection != selectedAlbum else { return }
        selectedAlbum = selection
        if let data = try? JSONEncoder().encode(selection) {
            userDefaults.set(data, forKey: Self.selectionStorageKey)
        }
        applySelection()
    }

    /// Rebuilds `assets` for `selectedAlbum` and restores that album's cursor.
    private func applySelection() {
        let selection = selectedAlbum
        assets = allAssets.filter { selection.contains(dateKeys[$0.localIdentifier]) }
        currentIndex = min(progressByAlbum[selection] ?? 0, assets.count)
        phase = currentIndex >= assets.count ? .finished : .browsing
    }

    private func albumExists(_ selection: AlbumSelection) -> Bool {
        switch selection {
        case .all:
            return true
        case .year(let year):
            return yearAlbums.contains { $0.year == year }
        case .month(let year, let month):
            return yearAlbums.first { $0.year == year }?.months.contains { $0.key.month == month } ?? false
        }
    }

    /// Recomputes counts and covers from `allAssets`. O(n) over identifiers – called on
    /// load and on library changes, not on every swipe.
    private func rebuildAlbums() {
        var counts: [DateKey: Int] = [:]
        var covers: [DateKey: PHAsset] = [:]
        // `allAssets` is newest-first, so the first asset seen per key is the cover.
        for asset in allAssets {
            guard let key = dateKeys[asset.localIdentifier] else { continue }
            counts[key, default: 0] += 1
            if covers[key] == nil { covers[key] = asset }
        }

        var byYear: [Int: [MonthAlbum]] = [:]
        for (key, count) in counts {
            byYear[key.year, default: []].append(MonthAlbum(key: key, count: count, cover: covers[key]))
        }
        yearAlbums = byYear.keys.sorted(by: >).map { year in
            YearAlbum(year: year, months: byYear[year]!.sorted { $0.key > $1.key })
        }
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
        rebuildAlbums()
    }

    /// Puts the most recently queued photo back on top of the deck (if it belongs to
    /// the current album) and back into the library list either way.
    func undoLastQueuedDeletion() {
        guard let asset = pendingDeletions.popLast() else { return }
        persistPendingQueue()
        insertIntoLibrary(asset)
        if selectedAlbum.contains(dateKeys[asset.localIdentifier]) {
            assets.insert(asset, at: min(currentIndex, assets.count))
            if phase == .finished { phase = .browsing }
        }
        rebuildAlbums()
    }

    /// Inserts `asset` into `allAssets` keeping newest-first order.
    private func insertIntoLibrary(_ asset: PHAsset) {
        guard !allAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        if dateKeys[asset.localIdentifier] == nil,
           let key = Self.dateKey(for: asset, calendar: .current) {
            dateKeys[asset.localIdentifier] = key
        }
        let date = asset.creationDate ?? .distantPast
        let index = allAssets.firstIndex { ($0.creationDate ?? .distantPast) < date } ?? allAssets.endIndex
        allAssets.insert(asset, at: index)
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
        if !removed.isEmpty {
            removeAssets(withIdentifiers: removed)
            let pendingBefore = pendingDeletions.count
            pendingDeletions.removeAll { removed.contains($0.localIdentifier) }
            if pendingDeletions.count != pendingBefore { persistPendingQueue() }
        }

        // New photos (camera, iCloud sync) join their album immediately. If they fall
        // in the current album they are appended so they get reviewed at the end.
        let pendingIDs = Set(pendingDeletions.map(\.localIdentifier))
        let inserted = details.insertedObjects.filter {
            $0.mediaType == .image && !pendingIDs.contains($0.localIdentifier)
        }
        if !inserted.isEmpty {
            for asset in inserted {
                insertIntoLibrary(asset)
                if selectedAlbum.contains(dateKeys[asset.localIdentifier]),
                   !assets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                    assets.append(asset)
                }
            }
            if phase == .finished, currentIndex < assets.count { phase = .browsing }
        }

        if !removed.isEmpty || !inserted.isEmpty { rebuildAlbums() }
    }

    private func removeAssets(withIdentifiers identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        allAssets.removeAll { identifiers.contains($0.localIdentifier) }
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
