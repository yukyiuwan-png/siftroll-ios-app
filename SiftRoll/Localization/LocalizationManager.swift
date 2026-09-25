//
//  LocalizationManager.swift
//  SiftRoll
//
//  Runtime language switching. SwiftUI's built-in `Text("key")` localization always
//  follows the *system* language, so to support an in-app toggle we load the
//  `Localizable.strings` bundle for the chosen language ourselves and expose a small
//  `t(_:)` lookup that views call.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    private static let storageKey = "SiftRoll.selectedLanguage"

    /// Currently active UI language. Changing it re-renders every observing view.
    @Published private(set) var language: AppLanguage

    private var activeBundle: Bundle
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = userDefaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        // First launch: follow the iPhone system language. Afterwards: respect the user's choice.
        let initial = stored ?? AppLanguage.detectFromSystem()
        language = initial
        activeBundle = Self.bundle(for: initial)
    }

    // MARK: - Switching

    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        activeBundle = Self.bundle(for: newLanguage)
        userDefaults.set(newLanguage.rawValue, forKey: Self.storageKey)
    }

    func toggleLanguage() {
        setLanguage(language.toggled)
    }

    /// Two-way binding for pickers in Settings.
    var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { self.language },
            set: { self.setLanguage($0) }
        )
    }

    // MARK: - Lookup

    /// Localized string for `key` in the active language.
    func t(_ key: String) -> String {
        string(for: key, in: activeBundle, language: language)
    }

    /// Localized, formatted string. Arguments are formatted with the active locale.
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: language.locale, arguments: arguments)
    }

    /// Localized string for `key` in a specific language (used for bilingual alerts).
    func t(_ key: String, in target: AppLanguage) -> String {
        string(for: key, in: Self.bundle(for: target), language: target)
    }

    /// Active-language text followed by the same text in the other language,
    /// e.g. for alerts the product spec wants shown bilingually.
    func bilingual(_ key: String, separator: String = "\n\n") -> String {
        t(key) + separator + t(key, in: language.toggled)
    }

    // MARK: - Private

    private func string(for key: String, in bundle: Bundle, language: AppLanguage) -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        // Missing translation: fall back to English rather than showing the raw key.
        if value == key, language != .english {
            return Self.bundle(for: .english).localizedString(forKey: key, value: nil, table: nil)
        }
        return value
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
