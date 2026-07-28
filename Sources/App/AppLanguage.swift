import SwiftUI
import Foundation
import ObjectiveC

// Swizzle Bundle.main so NSLocalizedString + SwiftUI Text resolve against a
// chosen .lproj at runtime , lets the user switch language live, no relaunch.
nonisolated(unsafe) private var ap_bundleKey: UInt8 = 0

private final class AnyLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &ap_bundleKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

private extension Bundle {
    static let ap_swizzleOnce: Void = { object_setClass(Bundle.main, AnyLanguageBundle.self) }()
    /// `code == nil` follows the system language.
    static func ap_setLanguage(_ code: String?) {
        _ = ap_swizzleOnce
        let path = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        objc_setAssociatedObject(Bundle.main, &ap_bundleKey, path, .OBJC_ASSOCIATION_RETAIN)
    }
}

@MainActor
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()

    enum Lang: String, CaseIterable, Identifiable {
        case system
        case en
        case vi
        case zh = "zh-Hans"
        case zhHant = "zh-Hant"
        var id: String { rawValue }
        /// Native label, shown in the picker (kept in each language's own script).
        var label: String {
            switch self {
            case .system: return NSLocalizedString("System", comment: "language option")
            case .en:     return "English"
            case .vi:     return "Tiếng Việt"
            case .zh:     return "简体中文"
            case .zhHant: return "繁體中文"
            }
        }
    }

    private static let key = "desktoppet.appLanguage"

    @Published var lang: Lang {
        didSet {
            UserDefaults.standard.set(lang.rawValue, forKey: Self.key)
            apply()
            PetController.shared.relocalize()
        }
    }

    private init() {
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
        apply()
    }

    /// Locale to feed `\.environment(\.locale, ...)` so SwiftUI re-resolves.
    var locale: Locale {
        switch lang {
        case .system: return Locale.current
        case .en:     return Locale(identifier: "en")
        case .vi:     return Locale(identifier: "vi")
        case .zh:     return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        }
    }

    private func apply() {
        Bundle.ap_setLanguage(lang == .system ? nil : lang.rawValue)
    }
}
