//
//  SiftRollApp.swift
//  SiftRoll
//
//  Entry point. Owns the two app-wide services (localization + photo library)
//  and injects them into the SwiftUI environment.
//

import SwiftUI

@main
struct SiftRollApp: App {
    /// Active UI language (auto-detected on first launch, user-toggleable afterwards).
    @StateObject private var localization = LocalizationManager()

    /// Thin wrapper around PHPhotoLibrary: authorization, fetching, image loading, deletion.
    @StateObject private var photoLibrary = PhotoLibraryService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(localization)
                .environmentObject(photoLibrary)
                // Drives system formatting (dates, numbers) so it follows the in-app language,
                // not only the device language.
                .environment(\.locale, localization.language.locale)
                .preferredColorScheme(.dark)
                .tint(.brandPrimary)
        }
    }
}
