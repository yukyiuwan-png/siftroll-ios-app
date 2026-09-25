//
//  PermissionView.swift
//  SiftRoll
//
//  Onboarding / permission screen. Shown until the user grants *full* photo library
//  access. Limited ("Select Photos…") and denied states explain why full access is
//  needed and deep-link to the Settings app.
//

import SwiftUI

@MainActor
struct PermissionView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.openURL) private var openURL

    @State private var isRequesting = false
    @State private var showsFullAccessAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                backgroundGlow

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        logo
                            .padding(.top, 24)

                        VStack(spacing: 8) {
                            Text(l10n.t("app.name"))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(l10n.t("app.slogan"))
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(l10n.t("app.slogan.alt"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)

                        Text(l10n.t("permission.intro"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        featureList

                        if let statusKey {
                            statusBanner(text: l10n.t(statusKey))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) {
                    actionArea
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(
                            LinearGradient(colors: [.clear, .appBackground, .appBackground],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea()
                        )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageToggleButton()
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert(l10n.t("permission.required.title"), isPresented: $showsFullAccessAlert) {
                Button(l10n.t("common.openSettings")) { openSystemSettings() }
                Button(l10n.t("common.notNow"), role: .cancel) {}
            } message: {
                Text(l10n.bilingual("permission.required.message"))
            }
            .onAppear {
                // Returning users who previously chose limited access get the explanation right away.
                if library.authorization == .limited { showsFullAccessAlert = true }
            }
            .onChange(of: library.authorization) { _, newValue in
                if newValue == .limited || newValue == .denied {
                    showsFullAccessAlert = true
                }
            }
        }
    }

    // MARK: - Pieces

    private var backgroundGlow: some View {
        RadialGradient(colors: [Color.brandPrimary.opacity(0.35), .clear],
                       center: .init(x: 0.5, y: 0.18),
                       startRadius: 10,
                       endRadius: 320)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var logo: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.brandPrimary.opacity(0.45), radius: 30, y: 12)
            .accessibilityHidden(true)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "hand.draw.fill", color: .brandSuccess, key: "permission.feature.swipe")
            featureRow(icon: "trash.fill", color: .brandDanger, key: "permission.feature.recentlyDeleted")
            featureRow(icon: "lock.shield.fill", color: .brandPrimary, key: "permission.feature.private")
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func featureRow(icon: String, color: Color, key: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(l10n.t(key))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func statusBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if isRequesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: needsSettings ? "gear" : "photo.on.rectangle.angled")
                    }
                    Text(l10n.t(needsSettings ? "permission.button.settings" : "permission.button.request"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .disabled(isRequesting)

            Text(l10n.t("permission.footnote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Logic

    /// Once the system dialog has been answered, the only way to change the
    /// permission is through the Settings app.
    private var needsSettings: Bool {
        library.authorization != .notDetermined
    }

    private var statusKey: String? {
        switch library.authorization {
        case .limited: return "permission.status.limited"
        case .denied: return "permission.status.denied"
        case .restricted: return "permission.status.restricted"
        case .notDetermined, .full: return nil
        }
    }

    private func primaryAction() {
        if needsSettings {
            openSystemSettings()
        } else {
            isRequesting = true
            Task {
                await library.requestAuthorization()
                isRequesting = false
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    PermissionView()
        .environmentObject(LocalizationManager())
        .environmentObject(PhotoLibraryService())
        .preferredColorScheme(.dark)
}
