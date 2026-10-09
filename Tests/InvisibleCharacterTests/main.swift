// CLI test runner for InvisibleCharacters: classification and the
// display-only substitution behind revealed characters (#19).

import AppKit

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("  ok  \(name)") }
    else { failed += 1; print("FAIL  \(name)") }
}

func kind(_ scalar: UInt16) -> InvisibleCharacters.Kind? {
    InvisibleCharacters.kind(of: scalar)
}

func display(_ string: String) -> String {
    InvisibleCharacters.displayForm(of: string).text
}

// MARK: - Classification

do {
    for unit: UInt16 in [0x200B, 0x2060, 0xFEFF] {
        expect(kind(unit) == .zeroWidth, String(format: "U+%04X is zero-width", unit))
    }
    for unit: UInt16 in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069] {
        expect(kind(unit) == .bidiControl, String(format: "U+%04X is a bidi control", unit))
    }
    for unit: UInt16 in [0x00A0, 0x202F, 0x2007, 0x3000] {
        expect(kind(unit) == .unusualSpace, String(format: "U+%04X is an unusual space", unit))
    }
    var allControls = true
    for unit: UInt16 in 0x00...0x1F where unit != 0x09 && unit != 0x0A && unit != 0x0D {
        allControls = allControls && kind(unit) == .controlCode
    }
    expect(allControls, "C0 controls other than tab/LF/CR are control codes")
    expect(kind(0x7F) == .controlCode, "DEL is a control code")
}

do {
    // Ordinary whitespace, ZWJ/ZWNJ, LRM/RLM, and line/paragraph separators stay unmarked.
    for unit: UInt16 in [0x20, 0x09, 0x0A, 0x0D, 0x200C, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0x00AD, 0x2009, 0x61] {
        expect(kind(unit) == nil, String(format: "U+%04X is not marked", unit))
    }
}

do {
    // The pre-check set agrees with kind(of:) over the whole BMP.
    var mismatches = 0
    for unit in UInt16(0)...UInt16(0xFFFF) {
        guard let scalar = Unicode.Scalar(unit) else { continue }
        if InvisibleCharacters.markedSet.contains(scalar) != (kind(unit) != nil) { mismatches += 1 }
    }
    expect(mismatches == 0, "markedSet matches kind(of:) (\(mismatches) mismatches)")
}

// MARK: - Display form

do {
    expect(display("a\u{200B}b") == "a\u{2009}b", "zero-width space shows as a thin space")
    expect(display("\u{FEFF}x") == "\u{2009}x", "stray BOM shows as a thin space")
    expect(display("a\u{00A0}b") == "a\u{00A0}b", "NBSP keeps its own character")
    expect(display("\u{0000}\u{001B}\u{007F}") == "\u{2400}\u{241B}\u{2421}", "controls show as Control Pictures")
    expect(display("a\tb\nc d") == "a\tb\nc d", "ordinary whitespace untouched")
}

do {
    let family = "👨\u{200D}👩\u{200D}👧"
    let r = InvisibleCharacters.displayForm(of: family)
    expect(r.text == family && r.marks.isEmpty, "ZWJ inside an emoji family untouched")
    let persian = "می\u{200C}خواهم \u{200F}x\u{200E}"
    let p = InvisibleCharacters.displayForm(of: persian)
    expect(p.text == persian && p.marks.isEmpty, "ZWNJ, RLM and LRM untouched")
}

do {
    let input = "😀\u{200B}é\u{0007}\u{202E}日本\u{3000}語\u{2066}🇰🇷\n"
    let r = InvisibleCharacters.displayForm(of: input)
    expect(r.text.utf16.count == input.utf16.count, "display has the same UTF-16 length")
    expect(r.marks.map(\.location) == [2, 4, 5, 8, 10], "marks sit at the input's UTF-16 offsets")
    expect(r.marks.map(\.kind) == [.zeroWidth, .controlCode, .bidiControl, .unusualSpace, .bidiControl], "mark kinds")
    var others = true
    let i = Array(input.utf16), d = Array(r.text.utf16)
    for offset in i.indices where !r.marks.contains(where: { $0.location == offset }) {
        others = others && i[offset] == d[offset]
    }
    expect(others, "unmarked UTF-16 units are untouched (surrogate pairs intact)")
}

do {
    // Trojan Source (CVE-2021-42574): RLO … LRI hides `return` order in display.
    let line = "if access_level != \"user\u{202E} \u{2066}// Check if admin\u{2069} \u{2066}\" {"
    let shown = display(line)
    let bidi = shown.unicodeScalars.contains { (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }
    expect(!bidi, "Trojan Source line has no bidi controls left in display")
    expect(shown == line
        .replacingOccurrences(of: "\u{202E}", with: "\u{2009}")
        .replacingOccurrences(of: "\u{2066}", with: "\u{2009}")
        .replacingOccurrences(of: "\u{2069}", with: "\u{2009}"), "Trojan Source line reads in stored order")
}

// MARK: - Attributed paragraph

do {
    let plain = NSAttributedString(string: "nothing to see\n")
    expect(InvisibleCharacters.displayParagraph(plain) == nil, "unmarked paragraph returns nil")
}

do {
    let bold = NSFont.boldSystemFont(ofSize: 14)
    let source = NSMutableAttributedString(string: "**a\u{200B}b** c\u{0001}\n", attributes: [.font: NSFont.systemFont(ofSize: 14)])
    source.addAttribute(.font, value: bold, range: NSRange(location: 2, length: 3))
    source.addAttribute(.foregroundColor, value: EditorTheme.markerColor, range: NSRange(location: 0, length: 2))
    let shown = InvisibleCharacters.displayParagraph(source)
    expect(shown?.length == source.length, "attributed display keeps the length")
    expect(shown?.string == "**a\u{2009}b** c\u{2401}\n", "attributed display substitutes")
    expect(shown?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == bold, "substituted character keeps the styler's font")
    expect(shown?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont == bold, "neighbor keeps the styler's font")
    expect(shown?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == EditorTheme.markerColor, "marker color preserved")
    expect(shown?.attribute(.backgroundColor, at: 3, effectiveRange: nil) as? NSColor == EditorTheme.invisibleCharacterColor, "zero-width gets the tint")
    expect(shown?.attribute(.backgroundColor, at: 4, effectiveRange: nil) == nil, "tint covers only the marked character")
    expect(shown?.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor == EditorTheme.controlPictureColor, "control picture dimmed")
    expect(source.string == "**a\u{200B}b** c\u{0001}\n", "source is not mutated")
}

do {
    let source = NSAttributedString(string: "10\u{00A0}km\n")
    let shown = InvisibleCharacters.displayParagraph(source)
    expect(shown?.string == source.string, "NBSP is an attribute-only change")
    expect(shown?.attribute(.backgroundColor, at: 2, effectiveRange: nil) as? NSColor == EditorTheme.unusualSpaceColor, "NBSP gets the fainter space tint")
}

do {
    // A full-width space is an em wide; it takes the fainter tint, while a
    // zero-width mark in the same paragraph keeps the stronger one.
    let shown = InvisibleCharacters.displayParagraph(NSAttributedString(string: "\u{3000}本日\u{200B}は\n"))
    expect(shown?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == EditorTheme.unusualSpaceColor, "full-width space gets the fainter space tint")
    expect(shown?.attribute(.backgroundColor, at: 3, effectiveRange: nil) as? NSColor == EditorTheme.invisibleCharacterColor, "zero-width keeps the stronger tint")
}

// MARK: - Content storage delegate

do {
    let storage = NSTextStorage(string: "clean\nkey\u{00A0}: v\u{200B}\n")
    let contentStorage = NSTextContentStorage()
    contentStorage.textStorage = storage
    let revealer = InvisibleCharacterRevealer.shared
    expect(revealer.textContentStorage(contentStorage, textParagraphWith: NSRange(location: 0, length: 6)) == nil, "delegate leaves a clean paragraph to TextKit")
    let paragraph = revealer.textContentStorage(contentStorage, textParagraphWith: NSRange(location: 6, length: 9))
    expect(paragraph?.attributedString.string == "key\u{00A0}: v\u{2009}\n", "delegate substitutes a marked paragraph")
    expect(storage.string == "clean\nkey\u{00A0}: v\u{200B}\n", "storage text unchanged")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
