import Foundation

/// Standard bundle localization; language selection and fallback belong to macOS.
enum L10n {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
