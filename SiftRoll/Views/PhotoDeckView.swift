//
//  PhotoDeckView.swift
//  SiftRoll
//
//  The core screen: a full-screen photo card you swipe right to keep or left to
//  delete, with the next card peeking from behind, a progress line and fallback
//  buttons for users who prefer tapping.
//

import SwiftUI
import Photos

@MainActor
struct PhotoDeckView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.displayScale) private var displayScale

    @StateObject private var model: PhotoDeckViewModel

    /// Horizontal offset of the top card. Owned here so alerts can hold / reset it.
    @State private var cardOffset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showsSettings = false

    init(library: PhotoLibraryService) {
        _model = StateObject(wrappedValue: PhotoDeckViewModel(library: library))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                switch model.phase {
                case .loading:
                    loadingView
                case .finished:
                    DeckFinishedView(keptCount: model.keptCount,
                                     deletedCount: model.deletedCount,
                                     pendingCount: model.pendingCount,
                                     isLibraryEmpty: model.totalCount == 0 && model.pendingCount == 0,
                                     isDeleting: model.isDeleting,
                                     onCommit: { Task { await commitPendingDeletions() } },
                                     onRestart: { model.restart() })
                case .browsing:
                    deck
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { brandTitle }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        LanguageToggleButton()
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                        .accessibilityLabel(l10n.t("settings.button.accessibility"))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
            // 1) One-time in-app notice, shown on the first left swipe of the session.
            //    After it is acknowledged, left swipes queue photos without any prompt.
            .alert(l10n.t("delete.notice.title"), isPresented: $model.isShowingDeletionNotice) {
                Button(l10n.t("delete.notice.action")) {
                    model.acknowledgeDeletionNotice()
                    queueCurrentCard()
                }
                Button(l10n.t("common.cancel"), role: .cancel) {
                    springBack()
                }
            } message: {
                Text(l10n.bilingual("delete.notice.message"))
            }
            // 2) Error feedback when PhotoKit refuses the deletion.
            .alert(l10n.t("delete.failed.title"),
                   isPresented: isShowingErrorAlert,
                   presenting: model.activeAlert) { _ in
                Button(l10n.t("common.ok"), role: .cancel) {}
            } message: { alert in
                switch alert {
                case .deletionFailed(let detail):
                    Text(l10n.t("delete.failed.message", detail))
                }
            }
            .task {
                if !model.hasLoaded { model.loadLibrary() }
            }
        }
    }

    private var isShowingErrorAlert: Binding<Bool> {
        Binding(
            get: { model.activeAlert != nil },
            set: { if !$0 { model.activeAlert = nil } }
        )
    }

    // MARK: - Sections

    private var brandTitle: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(l10n.t("app.name"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text(l10n.t("deck.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var deck: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack {
                    // Next card peeks from behind so the deck feels like a stack.
                    if let next = model.nextAsset {
                        PhotoCardView(asset: next)
                            .scaleEffect(0.94)
                            .opacity(0.55)
                            .id("behind-\(next.localIdentifier)")
                            .allowsHitTesting(false)
                    }

                    if let current = model.currentAsset {
                        SwipeCardView(offset: $cardOffset, onSwipe: { handleSwipe($0) }) {
                            PhotoCardView(asset: current, onSkip: { advanceWithoutDecision() })
                        }
                        .id(current.localIdentifier)
                        .disabled(isAnimatingOut || model.isDeleting)
                    }
                }
                .onChange(of: model.currentIndex, initial: true) { _, _ in
                    let target = PhotoLibraryService.targetPixelSize(for: geo.size, displayScale: displayScale)
                    library.prefetch(model.upcomingAssets(), targetSize: target)
                }
            }
            .padding(.horizontal, 12)

            footer
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 40) {
                roundButton(icon: "xmark", color: .brandDanger, labelKey: "deck.action.delete") {
                    swipeProgrammatically(.left)
                }

                VStack(spacing: 2) {
                    Text(l10n.t("deck.progress",
                                model.displayPosition.formatted(.number.locale(l10n.language.locale)),
                                model.totalCount.formatted(.number.locale(l10n.language.locale))))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(l10n.t("deck.remaining",
                                model.remainingCount.formatted(.number.locale(l10n.language.locale))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 110)

                roundButton(icon: "checkmark", color: .brandSuccess, labelKey: "deck.action.keep") {
                    swipeProgrammatically(.right)
                }
            }

            if model.pendingCount > 0 {
                pendingBar
            } else {
                Text(l10n.t("deck.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.pendingCount > 0)
    }

    /// Shows how many photos are queued and commits them all with one system sheet.
    private var pendingBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.impact(.light)
                withAnimation(.snappy(duration: 0.25)) { model.undoLastQueuedDeletion() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(model.isDeleting || isAnimatingOut)
            .accessibilityLabel(l10n.t("deck.pending.undo"))

            Button {
                Task { await commitPendingDeletions() }
            } label: {
                HStack(spacing: 8) {
                    if model.isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(l10n.t("deck.pending.commit", formatted(model.pendingCount)))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.brandDanger, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isDeleting)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.locale(l10n.language.locale))
    }

    private func roundButton(icon: String, color: Color, labelKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(isAnimatingOut || model.isDeleting)
        .accessibilityLabel(l10n.t(labelKey))
    }

    // MARK: - Swipe handling

    private func handleSwipe(_ direction: SwipeDirection) {
        switch direction {
        case .right:
            Haptics.notify(.success)
            flyAway(.right) {
                model.keepCurrent()
            }
        case .left:
            if model.needsDeletionNotice {
                // First delete of the session: hold the card (red overlay visible)
                // while the one-time notice explains what happens.
                model.presentDeletionNotice()
            } else {
                queueCurrentCard()
            }
        }
    }

    /// Fallback buttons drive the same flow as a real swipe.
    private func swipeProgrammatically(_ direction: SwipeDirection) {
        guard model.currentAsset != nil else { return }
        switch direction {
        case .right:
            handleSwipe(.right)
        case .left:
            if model.needsDeletionNotice {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    cardOffset = CGSize(width: -Metrics.swipeThreshold, height: 0)
                }
            }
            handleSwipe(.left)
        }
    }

    /// Card leaves immediately; the photo waits in the pending queue. No PhotoKit
    /// call and therefore no system sheet until the batch is committed.
    private func queueCurrentCard() {
        Haptics.impact(.rigid)
        flyAway(.left) {
            model.queueCurrentForDeletion()
        }
    }

    /// One `deleteAssets` call for the whole queue → a single system confirmation.
    private func commitPendingDeletions() async {
        let deleted = await model.commitPendingDeletions()
        if deleted { Haptics.notify(.success) }
    }

    /// Slides the card off-screen, then applies `completion` and resets the offset
    /// without animation so the next card appears centred.
    private func flyAway(_ direction: SwipeDirection, completion: @escaping () -> Void) {
        isAnimatingOut = true
        let distance: CGFloat = direction == .right ? 700 : -700
        withAnimation(.easeOut(duration: 0.3)) {
            cardOffset = CGSize(width: distance, height: 40)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                completion()
                cardOffset = .zero
            }
            isAnimatingOut = false
        }
    }

    private func springBack() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            cardOffset = .zero
        }
    }

    private func advanceWithoutDecision() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.skipCurrent()
            cardOffset = .zero
        }
    }
}
