//
//  RootView.swift
//  SiftRoll
//
//  Routes between the permission screen and the card deck based on the current
//  photo library authorization.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch library.authorization {
            case .full:
                PhotoDeckView(library: library)
                    .transition(.opacity)
            case .notDetermined, .limited, .denied, .restricted:
                PermissionView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: library.authorization)
        // The user may have changed the permission in Settings while we were in the background.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                library.refreshAuthorization()
            }
        }
    }
}
