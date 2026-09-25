//
//  SwipeOverlayView.swift
//  SiftRoll
//
//  Tinted overlay + stamp label drawn over the card while dragging:
//  green "Keep / 保留" when dragging right, red "Delete / 刪除" when dragging left.
//

import SwiftUI

enum SwipeDirection {
    case left   // delete
    case right  // keep
}

struct SwipeOverlayView: View {
    @EnvironmentObject private var l10n: LocalizationManager

    let direction: SwipeDirection?
    /// 0…1 – how close the drag is to the swipe threshold.
    let progress: CGFloat

    var body: some View {
        ZStack(alignment: direction == .right ? .topLeading : .topTrailing) {
            tint.opacity(0.42 * progress)

            if let direction {
                stamp(for: direction)
                    .padding(26)
                    .rotationEffect(.degrees(direction == .right ? -12 : 12))
                    .scaleEffect(0.8 + 0.2 * progress)
                    .opacity(progress)
            }
        }
        .allowsHitTesting(false)
    }

    private var tint: Color {
        switch direction {
        case .right: return .brandSuccess
        case .left: return .brandDanger
        case nil: return .clear
        }
    }

    /// Big label in the active language, with the other language underneath so the
    /// stamp always reads bilingually (e.g. "Keep" / "保留").
    private func stamp(for direction: SwipeDirection) -> some View {
        let key = direction == .right ? "swipe.keep" : "swipe.delete"
        let icon = direction == .right ? "checkmark" : "trash"
        return VStack(alignment: direction == .right ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .heavy))
                Text(l10n.t(key))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
            }
            Text(l10n.t(key, in: l10n.language.toggled))
                .font(.headline.weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint, lineWidth: 4)
        )
    }
}

#Preview("Keep") {
    SwipeOverlayView(direction: .right, progress: 1)
        .environmentObject(LocalizationManager())
        .frame(width: 360, height: 640)
        .background(Color.gray)
}

#Preview("Delete") {
    SwipeOverlayView(direction: .left, progress: 1)
        .environmentObject(LocalizationManager())
        .frame(width: 360, height: 640)
        .background(Color.gray)
}
