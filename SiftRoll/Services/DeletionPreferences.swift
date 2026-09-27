//
//  DeletionPreferences.swift
//  SiftRoll
//
//  Decides whether the in-app "Before You Delete" notice should be shown.
//  Lives at app level (injected from `SiftRollApp`) so the once-per-session flag
//  cannot be reset by SwiftUI rebuilding the deck view.
//

import Foundation
import Combine

@MainActor
final class DeletionPreferences: ObservableObject {
    private static let rememberKey = "SiftRoll.skipDeletionNotice"

    /// "Remember my setting" was ticked: never show the notice again, across launches.
    @Published var skipNoticePermanently: Bool {
        didSet { userDefaults.set(skipNoticePermanently, forKey: Self.rememberKey) }
    }

    /// The notice was acknowledged during this app session (memory only).
    @Published private(set) var hasAcknowledgedThisSession = false

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        skipNoticePermanently = userDefaults.bool(forKey: Self.rememberKey)
    }

    /// True only for the very first delete attempt that still needs the explanation.
    var shouldShowNotice: Bool {
        !skipNoticePermanently && !hasAcknowledgedThisSession
    }

    /// Called when the user taps "Got It". `remember` mirrors the checkbox.
    func acknowledge(remember: Bool) {
        hasAcknowledgedThisSession = true
        if remember { skipNoticePermanently = true }
    }
}
