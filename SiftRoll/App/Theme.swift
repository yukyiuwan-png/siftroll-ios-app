//
//  Theme.swift
//  SiftRoll
//
//  Design tokens shared across the app. Colors are defined in Assets.xcassets so
//  they can be tweaked without touching code.
//

import SwiftUI
import UIKit

extension Color {
    /// #3478F6 – primary actions, active language pill, links.
    static let brandPrimary = Color("BrandPrimary")
    /// #34C759 – "Keep" overlay and button.
    static let brandSuccess = Color("BrandSuccess")
    /// #FF3B30 – "Delete" overlay and button.
    static let brandDanger = Color("BrandDanger")
    /// #000000 – app background (pure black for OLED).
    static let appBackground = Color.black
    /// Dark card surface shown behind photos while they load.
    static let cardSurface = Color(white: 0.09)
}

enum Metrics {
    /// Corner radius of the photo card.
    static let cardCornerRadius: CGFloat = 28
    /// Horizontal drag distance (in points) required to trigger a swipe.
    static let swipeThreshold: CGFloat = 120
    /// Maximum pinch-to-zoom scale.
    static let maxZoomScale: CGFloat = 4
}

/// Tiny wrapper over UIKit haptics so views stay declarative.
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

extension Bundle {
    /// "1.0 (1)" style version string for the About section.
    var displayVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
