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
    /// True when the library had no photos at all (as opposed to "you finished").
    let isLibraryEmpty: Bool
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
                Text(l10n.t(isLibraryEmpty ? "deck.empty.title" : "deck.finished.title"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(l10n.t(isLibraryEmpty ? "deck.empty.message" : "deck.finished.message"))
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

            Spacer()

            Button(action: onRestart) {
                Label(l10n.t("deck.finished.restart"), systemImage: "arrow.counterclockwise")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
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
    DeckFinishedView(keptCount: 42, deletedCount: 17, isLibraryEmpty: false) {}
        .environmentObject(LocalizationManager())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
