import Foundation

@main
struct LocalizationChecks {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let appPath = CommandLine.arguments[1]
        guard let app = Bundle(path: appPath),
              let resources = app.resourceURL,
              let english = Bundle(url: resources.appendingPathComponent("en.lproj")),
              let englishURL = english.url(forResource: "Localizable", withExtension: "strings") else {
            fatalError("Built app or English localization is missing")
        }
        let base = try PropertyListSerialization.propertyList(from: Data(contentsOf: englishURL), format: nil) as! [String: String]
        require(app.localizations.count == 34, "Expected 34 bundled languages")
        let specifier = try NSRegularExpression(pattern: "%[@d]")
        for language in app.localizations.sorted() {
            let matched = Bundle.preferredLocalizations(from: app.localizations, forPreferences: [language])
            require(matched.first == language, "Language negotiation failed: \(language)")
            let localizedBundle = Bundle(url: resources.appendingPathComponent("\(language).lproj"))!
            let tableURL = localizedBundle.url(forResource: "Localizable", withExtension: "strings")!
            let table = try PropertyListSerialization.propertyList(from: Data(contentsOf: tableURL), format: nil) as! [String: String]
            require(Set(table.keys) == Set(base.keys), "Missing or extra keys: \(language)")
            for (key, englishText) in base {
                let value = localizedBundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
                require(!value.isEmpty && value != "__MISSING__", "Empty translation: \(language): \(key)")
                func placeholders(_ string: String) -> [String] {
                    specifier.matches(in: string, range: NSRange(string.startIndex..., in: string)).map {
                        String(string[Range($0.range, in: string)!])
                    }
                }
                let expected = placeholders(englishText)
                require(placeholders(value) == expected, "Format mismatch: \(language): \(key)")
                let arguments: [CVarArg] = expected.enumerated().map { index, spec in
                    spec == "%d" ? Int32(-50) as CVarArg : (index == 0 ? "Studio Display" : "Output") as CVarArg
                }
                let rendered = String(format: value, locale: Locale(identifier: language), arguments: arguments)
                require(placeholders(rendered).isEmpty, "Unexpanded placeholder: \(language): \(key)")
            }
        }
        require(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["fr-CA"]).first == "fr", "French regional fallback")
        require(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["zh-TW"]).first == "zh-Hant", "Traditional Chinese fallback")
        require(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["zh-CN"]).first == "zh-Hans", "Simplified Chinese fallback")
        print("PASS: \(app.localizations.count) languages × \(base.count) strings, bundle lookup, formatting, and regional fallback")
    }
}
