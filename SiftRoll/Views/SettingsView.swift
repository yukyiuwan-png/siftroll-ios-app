//
//  SettingsView.swift
//  SiftRoll
//
//  Language switch, privacy notes, gesture cheat-sheet and About.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var deletionPreferences: DeletionPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                howItWorksSection
                deletionSection
                privacySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(l10n.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var languageSection: some View {
        Section {
            Picker(selection: l10n.languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    HStack {
                        Text(language.nativeName)
                        Spacer()
                        Text(language.shortLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tag(language)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } header: {
            Label(l10n.t("settings.language.section"), systemImage: "globe")
        } footer: {
            Text(l10n.t("settings.language.footer"))
        }
    }

    private var howItWorksSection: some View {
        Section(l10n.t("settings.howItWorks.section")) {
            gestureRow(icon: "arrow.right.circle.fill", color: .brandSuccess, key: "settings.howItWorks.keep")
            gestureRow(icon: "arrow.left.circle.fill", color: .brandDanger, key: "settings.howItWorks.delete")
            gestureRow(icon: "arrow.up.left.and.arrow.down.right.circle.fill", color: .brandPrimary, key: "settings.howItWorks.zoom")
        }
    }

    /// Lets the user undo "Remember my setting" and see the deletion notice again.
    private var deletionSection: some View {
        Section {
            Toggle(isOn: showsDeletionNotice) {
                Label {
                    Text(l10n.t("settings.deletion.showNotice"))
                } icon: {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundStyle(.brandDanger)
                }
            }
            .tint(.brandPrimary)
        } header: {
            Text(l10n.t("settings.deletion.section"))
        } footer: {
            Text(l10n.t("settings.deletion.footer"))
        }
    }

    /// Inverse of the stored "skip" flag so the toggle reads positively.
    private var showsDeletionNotice: Binding<Bool> {
        Binding(
            get: { !deletionPreferences.skipNoticePermanently },
            set: { deletionPreferences.skipNoticePermanently = !$0 }
        )
    }

    private var privacySection: some View {
        Section(l10n.t("settings.privacy.section")) {
            Label {
                Text(l10n.t("settings.privacy.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.brandPrimary)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label(l10n.t("settings.privacy.photoPermission"), systemImage: "photo.badge.checkmark")
            }
        }
    }

    private var aboutSection: some View {
        Section(l10n.t("settings.about.section")) {
            HStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("app.name"))
                        .font(.title3.weight(.bold))
                    Text(l10n.t("app.slogan"))
                        .font(.subheadline)
                    Text(l10n.t("app.slogan.alt"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            Text(l10n.t("settings.about.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LabeledContent(l10n.t("settings.about.version"), value: Bundle.main.displayVersion)
        }
    }

    private func gestureRow(icon: String, color: Color, key: String) -> some View {
        Label {
            Text(l10n.t(key))
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(LocalizationManager())
        .environmentObject(DeletionPreferences())
}
