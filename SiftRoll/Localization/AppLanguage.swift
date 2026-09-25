//
//  AppLanguage.swift
//  SiftRoll
//
//  The two languages SiftRoll ships with. Raw values match the `.lproj` folder names
//  in Resources/ so the LocalizationManager can load the right bundle.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    /// Traditional Chinese with Hong Kong terminology (相片 / 相簿 / 取用 / 私隱 …).
    case traditionalChineseHK = "zh-HK"

    var id: String { rawValue }

    /// Name shown in Settings, always written in its own language.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .traditionalChineseHK: return "繁體中文（香港）"
        }
    }

    /// Compact label for the navigation bar toggle pill.
    var shortLabel: String {
        switch self {
        case .english: return "EN"
        case .traditionalChineseHK: return "繁中"
        }
    }

    /// Locale used for dates / numbers so they match the chosen UI language.
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en")
        case .traditionalChineseHK: return Locale(identifier: "zh_HK")
        }
    }

    /// The "other" language – used by the toggle button and bilingual alerts.
    var toggled: AppLanguage {
        self == .english ? .traditionalChineseHK : .english
    }

    /// Picks the best match from the user's preferred system languages.
    ///
    /// Mirrors iOS bundle resolution: walk the preferred list and return the first
    /// language we support. Any Traditional Chinese variant (zh-Hant, zh-HK, zh-TW,
    /// zh-MO, Cantonese) maps to the HK build; Simplified Chinese is not supported
    /// yet and falls through to English.
    static func detectFromSystem(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferredLanguages {
            let lower = identifier.lowercased()
            if lower.hasPrefix("en") {
                return .english
            }
            let isTraditionalChinese =
                lower.hasPrefix("yue") ||
                (lower.hasPrefix("zh") &&
                 (lower.contains("hant") || lower.contains("-hk") || lower.contains("-tw") || lower.contains("-mo")))
            if isTraditionalChinese {
                return .traditionalChineseHK
            }
        }
        return .english
    }
}
