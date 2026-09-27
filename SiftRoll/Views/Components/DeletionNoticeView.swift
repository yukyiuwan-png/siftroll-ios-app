//
//  DeletionNoticeView.swift
//  SiftRoll
//
//  Custom alert-style dialog for the one-time deletion notice. SwiftUI's `.alert`
//  cannot host a checkbox, so this replicates the iOS alert look (dimmed backdrop,
//  frosted card, stacked buttons) and adds a "Remember my setting" row.
//

import SwiftUI

struct DeletionNoticeView: View {
    @EnvironmentObject private var l10n: LocalizationManager

    let onConfirm: (_ remember: Bool) -> Void
    let onCancel: () -> Void

    @State private var remember = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.brandDanger)
                        .padding(.top, 4)

                    Text(l10n.t("delete.notice.title"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(l10n.bilingual("delete.notice.message"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    rememberRow
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

                Divider().overlay(Color.white.opacity(0.15))

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text(l10n.t("common.cancel"))
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundColor(Theme.brandPrimary)

                    Divider().overlay(Color.white.opacity(0.15)).frame(height: 48)

                    Button {
                        onConfirm(remember)
                    } label: {
                        Text(l10n.t("delete.notice.action"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundColor(Theme.brandPrimary)
                }
            }
            .frame(maxWidth: 300)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Color(white: 0.12).opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 32)
        }
        .accessibilityAddTraits(.isModal)
    }

    /// Checkbox: "Remember my setting / 記住我的設定".
    private var rememberRow: some View {
        Button {
            Haptics.impact(.light)
            remember.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: remember ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(remember ? Color.brandPrimary : Color.white.opacity(0.6))
                Text(l10n.bilingual("delete.notice.remember", separator: " / "))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(remember ? [.isSelected] : [])
        .accessibilityLabel(l10n.t("delete.notice.remember"))
    }
}

#Preview {
    ZStack {
        Color.gray
        DeletionNoticeView(onConfirm: { _ in }, onCancel: {})
    }
    .environmentObject(LocalizationManager())
    .preferredColorScheme(.dark)
}
