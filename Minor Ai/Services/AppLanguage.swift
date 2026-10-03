//
//  AppLanguage.swift
//  Minor Ai
//
//  The language Minor shows, chosen inside the app (Settings → Language) instead of in iOS
//  Settings. SwiftUI text follows the root view's locale; strings built in code use `L(_:)`,
//  which reads the chosen language's translations. AI answers default to it too.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    private static let key = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    // Only Minor's own text changes. The system's language list is left alone, so voice input
    // still recognizes the languages the person actually speaks.
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        bundleCache = nil
    }

    // The language actually shown: the chosen one, or the first system language Minor has.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let supported = Array(Set(Bundle.main.localizations + ["en"])).filter { $0 != "Base" }.sorted()
        let preferred = Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages).first
        return AppLanguage(rawValue: preferred ?? "en") ?? .english
    }

    // Language code for the server ("ru", "en").
    var code: String { resolved.rawValue }

    var locale: Locale { Locale(identifier: resolved.rawValue) }

    // The name of each language in itself, so people find their own in any interface language.
    var nativeName: String {
        switch self {
        case .system: return L("System")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    // Translations of the language shown (falls back to the main bundle, i.e. English).
    static var bundle: Bundle {
        if let bundleCache { return bundleCache }
        let code = current.resolved.rawValue
        let found = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        bundleCache = found
        return found
    }

    private static var bundleCache: Bundle?
}

// Localized text built in code (notices, errors, menus), in the language chosen in the app.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AppLanguage.bundle, locale: AppLanguage.current.locale)
}

// Lets the root view re-render in a new language right away.
@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    @Published private(set) var language = AppLanguage.current
    var reopenSettings = false

    func choose(_ language: AppLanguage) {
        guard language != self.language else { return }
        AppLanguage.set(language)
        reopenSettings = true
        self.language = language
    }
}
