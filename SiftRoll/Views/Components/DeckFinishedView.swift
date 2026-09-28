//
//  DeckFinishedView.swift
//  SiftRoll
//
//  Shown when every photo has been reviewed, or when the library is empty.
//

import SwiftUI

struct DeckFinishedView: View {
    @EnvironmentObject private var l10n: LocalizationManager

    let keptCount: Int
    let deletedCount: Int
    /// Photos swiped left that still wait for the single batch commit.
    let pendingCount: Int
    /// True when the library had no photos at all (as opposed to "you finished").
    let isLibraryEmpty: Bool
    /// True when only a year/month album was finished, not the whole library.
    let isAlbum: Bool
    let isDeleting: Bool
    let onCommit: () -> Void
    let onChooseAlbum: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: isLibraryEmpty ? "photo.on.rectangle.angled" : "checkmark.seal.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.brandPrimary, .brandSuccess],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: Color.brandPrimary.opacity(0.4), radius: 24)

            VStack(spacing: 10) {
                Text(l10n.t(titleKey))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(l10n.t(messageKey))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            if !isLibraryEmpty {
                HStack(spacing: 14) {
                    statChip(value: keptCount, labelKey: "deck.finished.kept", color: .brandSuccess, icon: "checkmark")
                    statChip(value: deletedCount, labelKey: "deck.finished.deleted", color: .brandDanger, icon: "trash")
                }
            }

            if pendingCount > 0 {
                Text(l10n.t("deck.finished.pending", formatted(pendingCount)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                if pendingCount > 0 {
                    Button(action: onCommit) {
                        HStack(spacing: 8) {
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text(l10n.t("deck.pending.commit", formatted(pendingCount)))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brandDanger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(isDeleting)
                }

                if !isLibraryEmpty {
                    Button(action: onChooseAlbum) {
                        Label(l10n.t("deck.finished.chooseAlbum"), systemImage: "calendar")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(pendingCount > 0 ? Color.white.opacity(0.1) : Color.brandPrimary,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .disabled(isDeleting)
                }

                Button(action: onRestart) {
                    Label(l10n.t("deck.finished.restart"), systemImage: "arrow.counterclockwise")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isLibraryEmpty ? Color.brandPrimary : Color.white.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(isDeleting)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    private var titleKey: String {
        if isLibraryEmpty { return "deck.empty.title" }
        return isAlbum ? "deck.finished.album.title" : "deck.finished.title"
    }

    private var messageKey: String {
        if isLibraryEmpty { return "deck.empty.message" }
        return isAlbum ? "deck.finished.album.message" : "deck.finished.message"
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.locale(l10n.language.locale))
    }

    private func statChip(value: Int, labelKey: String, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                Text(value.formatted(.number.locale(l10n.language.locale)))
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(color)
            Text(l10n.t(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    DeckFinishedView(keptCount: 42, deletedCount: 17, pendingCount: 5,
                     isLibraryEmpty: false, isAlbum: true, isDeleting: false,
                     onCommit: {}, onChooseAlbum: {}) {}
        .environmentObject(LocalizationManager())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
