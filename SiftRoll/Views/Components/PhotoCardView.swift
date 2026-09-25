//
//  PhotoCardView.swift
//  SiftRoll
//
//  Renders one `PHAsset` as a card: loading spinner → image (or an error state with
//  Retry / Skip). The image is requested on demand from PhotoKit at roughly the
//  card's pixel size; nothing is copied into the app.
//

import SwiftUI
import Photos

@MainActor
struct PhotoCardView: View {
    let asset: PHAsset
    /// Called from the error state when the user wants to move past an unloadable photo.
    var onSkip: (() -> Void)? = nil

    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var loadError: PhotoLibraryError?
    /// Incremented by "Retry" to re-run the loading task.
    @State private var reloadToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.cardSurface

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity)
                } else if let loadError {
                    errorView(for: loadError)
                } else {
                    loadingView
                }
            }
            .overlay(alignment: .bottom) {
                if image != nil { caption }
            }
            .task(id: PhotoLoadKey(assetID: asset.localIdentifier,
                                   token: reloadToken,
                                   width: Int(geo.size.width))) {
                await load(pointSize: geo.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text(l10n.t("deck.loadingPhoto"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(for error: PhotoLibraryError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: error.isCloudRelated ? "icloud.slash" : "photo.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(l10n.t("load.failed.title"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(l10n.t(error.isCloudRelated ? "load.failed.icloud" : "load.failed.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button(l10n.t("common.retry")) { reloadToken += 1 }
                    .buttonStyle(.borderedProminent)
                if let onSkip {
                    Button(l10n.t("common.skip"), action: onSkip)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Date + favourite badge along the bottom edge.
    private var caption: some View {
        HStack(spacing: 8) {
            if let date = asset.creationDate {
                Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
            }
            if asset.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel(l10n.t("photo.favorite"))
            }
            Spacer()
            Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 18)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Loading

    private func load(pointSize: CGSize) async {
        guard pointSize.width > 0, pointSize.height > 0 else { return }
        loadError = nil
        let targetSize = PhotoLibraryService.targetPixelSize(for: pointSize, displayScale: displayScale)

        do {
            let loaded = try await library.loadImage(for: asset, targetSize: targetSize)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        } catch PhotoLibraryError.cancelled {
            // View went away or a newer request superseded this one – nothing to show.
        } catch let error as PhotoLibraryError {
            loadError = error
        } catch {
            loadError = .underlying(error)
        }
    }
}

/// Identity of one image request; changing any field restarts the `.task`.
/// Width is included so the first real layout pass (not a zero-size pass) triggers a load.
private struct PhotoLoadKey: Hashable {
    let assetID: String
    let token: Int
    let width: Int
}

private extension PhotoLibraryError {
    var isCloudRelated: Bool {
        if case .assetInCloud = self { return true }
        return false
    }
}
