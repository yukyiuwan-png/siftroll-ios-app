//
//  AssetThumbnailView.swift
//  SiftRoll
//
//  Small square thumbnail for album rows. Loaded on demand from PhotoKit at a
//  low target size so long album lists stay cheap.
//

import SwiftUI
import Photos

struct AssetThumbnailView: View {
    let asset: PHAsset?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 10

    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.cardSurface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: asset?.localIdentifier) {
            image = nil
            guard let asset else { return }
            let pixels = size * displayScale * 2
            image = try? await library.loadImage(for: asset, targetSize: CGSize(width: pixels, height: pixels))
        }
        .accessibilityHidden(true)
    }
}
