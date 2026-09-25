//
//  SwipeCardView.swift
//  SiftRoll
//
//  Gesture container for the top card:
//  • Drag horizontally to swipe (spring back if the threshold isn't reached).
//  • Pinch to zoom the photo; while zoomed, dragging pans instead of swiping.
//  • Double-tap resets zoom.
//
//  The horizontal offset is owned by the parent (`PhotoDeckView`) so it can hold the
//  card while the delete confirmation is up, spring it back, or fly it off-screen.
//

import SwiftUI

struct SwipeCardView<Content: View>: View {
    @Binding var offset: CGSize
    let onSwipe: (SwipeDirection) -> Void
    @ViewBuilder let content: () -> Content

    // Pinch-to-zoom state. "steady" values are committed when a gesture ends.
    @State private var zoomScale: CGFloat = 1
    @State private var steadyZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var steadyPanOffset: CGSize = .zero
    @State private var hasCrossedThreshold = false

    private var isZoomed: Bool { steadyZoomScale > 1.02 || zoomScale > 1.02 }

    private var swipeProgress: CGFloat {
        min(1, abs(offset.width) / Metrics.swipeThreshold)
    }

    private var swipeDirection: SwipeDirection? {
        guard !isZoomed else { return nil }
        if offset.width > 8 { return .right }
        if offset.width < -8 { return .left }
        return nil
    }

    /// Slight tilt that follows the drag, like a physical card.
    private var rotation: Angle {
        .degrees(Double(max(-10, min(10, offset.width / 18))))
    }

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)

            content()
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(shape)
                .overlay {
                    SwipeOverlayView(direction: swipeDirection, progress: swipeProgress)
                        .clipShape(shape)
                }
                .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                .rotationEffect(rotation, anchor: .bottom)
                .offset(offset)
                .gesture(dragGesture(in: geo.size).simultaneously(with: magnifyGesture(in: geo.size)))
                .onTapGesture(count: 2) { resetZoom() }
                .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }

    // MARK: - Gestures

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                if isZoomed {
                    panOffset = CGSize(width: steadyPanOffset.width + value.translation.width,
                                       height: steadyPanOffset.height + value.translation.height)
                } else {
                    // Damp vertical movement so the card mostly slides sideways.
                    offset = CGSize(width: value.translation.width,
                                    height: value.translation.height * 0.35)
                    let crossed = abs(offset.width) >= Metrics.swipeThreshold
                    if crossed != hasCrossedThreshold {
                        hasCrossedThreshold = crossed
                        if crossed { Haptics.impact(.medium) }
                    }
                }
            }
            .onEnded { value in
                if isZoomed {
                    steadyPanOffset = clampedPan(panOffset, in: size)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panOffset = steadyPanOffset
                    }
                    return
                }

                hasCrossedThreshold = false
                let projected = value.predictedEndTranslation.width
                let threshold = Metrics.swipeThreshold

                if offset.width >= threshold || projected >= threshold * 2 {
                    onSwipe(.right)
                } else if offset.width <= -threshold || projected <= -threshold * 2 {
                    onSwipe(.left)
                } else {
                    // Didn't reach the threshold: bounce back to the centre.
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                        offset = .zero
                    }
                }
            }
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = min(max(steadyZoomScale * value.magnification, 0.85), Metrics.maxZoomScale)
            }
            .onEnded { _ in
                steadyZoomScale = min(max(zoomScale, 1), Metrics.maxZoomScale)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    zoomScale = steadyZoomScale
                    if steadyZoomScale <= 1 {
                        panOffset = .zero
                        steadyPanOffset = .zero
                    } else {
                        steadyPanOffset = clampedPan(panOffset, in: size)
                        panOffset = steadyPanOffset
                    }
                }
            }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomScale = 1
            steadyZoomScale = 1
            panOffset = .zero
            steadyPanOffset = .zero
        }
    }

    /// Keeps the zoomed photo from being panned completely out of the card.
    private func clampedPan(_ pan: CGSize, in size: CGSize) -> CGSize {
        let maxX = max(0, (size.width * steadyZoomScale - size.width) / 2)
        let maxY = max(0, (size.height * steadyZoomScale - size.height) / 2)
        return CGSize(width: min(max(pan.width, -maxX), maxX),
                      height: min(max(pan.height, -maxY), maxY))
    }
}
