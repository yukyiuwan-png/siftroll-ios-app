//
//  LanguageToggleButton.swift
//  SiftRoll
//
//  Compact "EN | 繁中" pill for the navigation bar. Tapping flips the language.
//

import SwiftUI

struct LanguageToggleButton: View {
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        Button {
            Haptics.impact(.light)
            withAnimation(.snappy(duration: 0.25)) {
                l10n.toggleLanguage()
            }
        } label: {
            HStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    let isActive = language == l10n.language
                    Text(language.shortLabel)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isActive ? Color.brandPrimary : .clear, in: Capsule())
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("language.toggle.accessibility"))
        .accessibilityValue(l10n.language.nativeName)
    }
}

#Preview {
    LanguageToggleButton()
        .environmentObject(LocalizationManager())
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
