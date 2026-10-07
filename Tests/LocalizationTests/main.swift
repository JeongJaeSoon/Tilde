// LocalizationTests — keeps the String Catalogs honest.
//
// Xcode fills Localizable.xcstrings automatically only when a developer
// builds in the IDE; on CI (and on a Command Line Tools-only machine) a new
// user-facing string would silently ship untranslated. This suite pins:
//
//   1. every localizable literal in the UI sources has a catalog entry
//   2. every catalog entry is translated into every shipped language
//   3. format placeholders (%lld, %@, …) survive translation intact
//   4. every document type name in Info.plist is in InfoPlist.xcstrings
//
// Runs from the repo root (Tests/run.sh cds there).

import Foundation

let shippedLanguages = ["ko", "ja", "zh-Hans"]
var failures = 0
var passes = 0

func check(_ condition: Bool, _ message: String) {
    if condition { passes += 1 } else { failures += 1; print("FAIL  \(message)") }
}

struct Catalog {
    let sourceLanguage: String
    /// key -> language -> value (only "translated" units count)
    let strings: [String: [String: String]]
    /// Entries Xcode manages that are deliberately not translated
    /// (`"shouldTranslate" : false` — e.g. CFBundleName, which stays "Tilde").
    let untranslated: Set<String>

    init(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        sourceLanguage = root["sourceLanguage"] as! String
        var out: [String: [String: String]] = [:]
        var skip = Set<String>()
        for (key, entry) in root["strings"] as! [String: Any] {
            if (entry as! [String: Any])["shouldTranslate"] as? Bool == false { skip.insert(key); continue }
            var perLang: [String: String] = [:]
            let localizations = (entry as! [String: Any])["localizations"] as? [String: Any] ?? [:]
            for (lang, loc) in localizations {
                let unit = (loc as! [String: Any])["stringUnit"] as! [String: Any]
                if unit["state"] as? String == "translated" {
                    perLang[lang] = unit["value"] as! String
                }
            }
            out[key] = perLang
        }
        strings = out
        untranslated = skip
    }
}

// MARK: - 1. Source literals are in the catalog

/// SwiftUI call sites whose string-literal argument is a LocalizedStringKey,
/// plus Foundation's explicit String(localized:).
let localizingCalls = ["Text(", "Button(", "Toggle(", "Picker(", "Section(", "Stepper(", ".help(", "String(localized:", "Label(", "CommandMenu("]

/// Converts a Swift interpolation to the printf-style key SwiftUI derives:
/// `\(Int(x))` → `%lld`, any other `\(…)` → `%@`.
func catalogKey(fromLiteral literal: String) -> String {
    var key = literal
    key = key.replacingOccurrences(of: #"\\\(Int\([^)]*\)\)"#, with: "%lld", options: .regularExpression)
    key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
    return key
}

/// Drops `//` comments (outside string literals) so commented-out UI or
/// prose mentioning Text("…") doesn't count as a call site.
func strippingLineComments(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        var inString = false
        var previous: Character = " "
        for (offset, ch) in line.enumerated() {
            if ch == "\"" && previous != "\\" { inString.toggle() }
            if !inString && ch == "/" && previous == "/" {
                return String(line.prefix(offset - 1))
            }
            previous = ch
        }
        return String(line)
    }.joined(separator: "\n")
}

/// Extracts every string literal inside each localizing call's balanced
/// parentheses — call sites may span lines (`Stepper(\n"…"`, `String(\n
/// localized: "…"`) and literals may hold interpolations with their own
/// parentheses (`"\(Int(x)) pt"`), so a line-based scan is not enough.
func localizableLiterals(inSource path: String) -> [String] {
    // `String(\n    localized: "…")` is written across lines; collapsing the
    // whitespace after every "(" lets one token match both spellings.
    let collapsed = strippingLineComments(try! String(contentsOfFile: path, encoding: .utf8))
        .replacingOccurrences(of: #"\(\s+"#, with: "(", options: .regularExpression)
    let text = Array(collapsed)
    var found: [String] = []

    /// Consumes a string literal starting at the opening quote; returns the
    /// index just past the closing quote and the raw literal body.
    func readLiteral(from start: Int) -> (end: Int, body: String) {
        var i = start + 1
        var body = ""
        while i < text.count {
            let ch = text[i]
            if ch == "\\" && i + 1 < text.count {
                if text[i + 1] == "(" {                 // interpolation: copy through its close paren
                    var depth = 0
                    repeat {
                        if text[i] == "(" { depth += 1 } else if text[i] == ")" { depth -= 1 }
                        body.append(text[i]); i += 1
                    } while depth > 0 && i < text.count
                    continue
                }
                body.append(ch); body.append(text[i + 1]); i += 2; continue
            }
            if ch == "\"" { return (i + 1, body) }
            body.append(ch); i += 1
        }
        return (i, body)
    }

    let source = String(text)
    for call in localizingCalls {
        var searchFrom = source.startIndex
        while let range = source.range(of: call, range: searchFrom..<source.endIndex) {
            searchFrom = range.upperBound
            var i = source.distance(from: source.startIndex, to: range.upperBound)   // just past "("
            var depth = 1
            while i < text.count && depth > 0 {
                let ch = text[i]
                if ch == "\"" {
                    let (end, body) = readLiteral(from: i)
                    if !body.isEmpty { found.append(catalogKey(fromLiteral: body)) }   // Button("") ⌘= catcher is skipped
                    i = end; continue
                }
                if ch == "(" { depth += 1 } else if ch == ")" { depth -= 1 }
                i += 1
            }
        }
    }
    return found
}

let uiSources = [
    "Tilde/App/TildeApp.swift",
    "Tilde/App/Updater.swift",
    "Tilde/App/FormatCommands.swift",
    "Tilde/Editor/EditorTextView+MarkdownEditing.swift",
    "Tilde/Editor/EditorView.swift",
    "Tilde/Settings/SettingsView.swift",
    "Tilde/Settings/AppSettings.swift",
    "Tilde/Document/TextDocument.swift",
    "Tilde/Reader/MarkdownRenderer.swift",
]

let localizable = try! Catalog(path: "Tilde/Localizable.xcstrings")
check(localizable.sourceLanguage == "en", "Localizable.xcstrings source language is en")

var referenced = Set<String>()
for source in uiSources {
    for key in localizableLiterals(inSource: source) {
        referenced.insert(key)
        check(localizable.strings[key] != nil, "\(source): \"\(key)\" has no entry in Localizable.xcstrings")
    }
}
check(referenced.count >= 20, "found a plausible number of UI literals (\(referenced.count))")
check(!referenced.contains(""), "no empty localizable literal (use Text(verbatim:) for placeholder labels)")
check(localizable.untranslated.isEmpty, "Localizable.xcstrings has no shouldTranslate=false entries (\(localizable.untranslated))")

for key in localizable.strings.keys {
    check(referenced.contains(key), "Localizable.xcstrings: \"\(key)\" is no longer referenced from source")
}

// MARK: - 2 & 3. Every entry fully translated, placeholders intact

func placeholders(in s: String) -> [String] {
    let re = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfsu]|%lld|%ld"#)
    let ns = s as NSString
    return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.sorted()
}

func checkTranslations(_ catalog: Catalog, name: String) {
    for (key, perLang) in catalog.strings {
        for lang in shippedLanguages {
            guard let value = perLang[lang] else {
                check(false, "\(name): \"\(key)\" is missing a \(lang) translation"); continue
            }
            check(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(name): \"\(key)\" has an empty \(lang) translation")
            check(placeholders(in: value) == placeholders(in: key),
                  "\(name): \"\(key)\" \(lang) placeholders \(placeholders(in: value)) ≠ \(placeholders(in: key))")
        }
    }
}

checkTranslations(localizable, name: "Localizable.xcstrings")

// MARK: - 4. Info.plist document type names

let infoPlist = try! Catalog(path: "Tilde/InfoPlist.xcstrings")
let plistData = try! Data(contentsOf: URL(fileURLWithPath: "Tilde/Info.plist"))
let plist = try! PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
let typeNames = (plist["CFBundleDocumentTypes"] as! [[String: Any]]).compactMap { $0["CFBundleTypeName"] as? String }
check(typeNames.count >= 3, "Info.plist declares document types")
for name in typeNames {
    check(infoPlist.strings[name] != nil, "InfoPlist.xcstrings: document type \"\(name)\" has no entry")
}
// Xcode adds the generated Info.plist keys on every build; they stay marked
// shouldTranslate=false (the app is "Tilde" in every language).
check(infoPlist.untranslated == ["CFBundleName", "NSHumanReadableCopyright"],
      "InfoPlist.xcstrings: only the Xcode-managed identity keys are untranslated (\(infoPlist.untranslated))")
checkTranslations(infoPlist, name: "InfoPlist.xcstrings")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
