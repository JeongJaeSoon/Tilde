//
//  InvisibleCharacters.swift
//  Tilde
//

import AppKit

/// Characters that draw as nothing, or exactly like an ordinary space, and
/// are nearly always a mistake in a text file: zero-width characters,
/// bidirectional controls, unusual spaces, and C0 control codes (#19).
///
/// The editor shows them through a display-only substitution: each marked
/// character is swapped for exactly one UTF-16 unit, so offsets in the
/// storage and on screen stay identical and selection, Find, the stylers,
/// and the gutter keep working on the real text. The file's bytes, copy,
/// and save never see the substitute.
///
/// Deliberately not marked: ordinary spaces, tabs and line breaks (CR
/// included — the buffer is LF-normalized, and a CR is a paragraph
/// separator to TextKit), ZWJ/ZWNJ (emoji sequences, several scripts), and
/// LRM/RLM (legitimate in right-to-left text).
nonisolated enum InvisibleCharacters {
    enum Kind: Equatable {
        /// U+200B, U+2060, and a stray U+FEFF (a real BOM is stripped at load).
        case zeroWidth
        /// U+202A–U+202E, U+2066–U+2069 (Trojan Source, CVE-2021-42574).
        case bidiControl
        /// U+00A0, U+202F, U+2007, U+3000: look exactly like a space.
        case unusualSpace
        /// U+0000–U+001F except tab, LF and CR; U+007F.
        case controlCode
    }

    static func kind(of unit: unichar) -> Kind? {
        switch unit {
        case 0x200B, 0x2060, 0xFEFF: .zeroWidth
        case 0x202A...0x202E, 0x2066...0x2069: .bidiControl
        case 0x00A0, 0x202F, 0x2007, 0x3000: .unusualSpace
        case 0x09, 0x0A, 0x0D: nil
        case 0x00...0x1F, 0x7F: .controlCode
        default: nil
        }
    }

    /// Every marked character, for a cheap "anything to do?" pre-check.
    static let markedSet: CharacterSet = {
        // Every marked character is a single BMP unit, so the set mirrors `kind(of:)`.
        var set = CharacterSet()
        for unit in UInt16(0x00)...UInt16(0x3000) where kind(of: unit) != nil {
            set.insert(Unicode.Scalar(unit)!)
        }
        set.insert("\u{FEFF}")
        return set
    }()

    /// The single UTF-16 unit shown in place of a marked character.
    ///
    /// Zero-width and bidirectional characters become a thin space (a small
    /// gap that the tint makes visible; dropping a bidi control from the
    /// display also drops its reordering, so the line reads in stored
    /// order). Unusual spaces keep their own glyph. Control codes become
    /// their Unicode Control Picture (U+2400 + code, U+2421 for DEL).
    static func displayUnit(for unit: unichar, kind: Kind) -> unichar {
        switch kind {
        case .zeroWidth, .bidiControl: 0x2009
        case .unusualSpace: unit
        case .controlCode: unit == 0x7F ? 0x2421 : 0x2400 + unit
        }
    }

    struct Mark: Equatable {
        /// UTF-16 offset, identical in the input and the display string.
        var location: Int
        var kind: Kind
    }

    /// The display form of `string` — the same UTF-16 length, with every
    /// marked character substituted — plus where the marks are.
    static func displayForm(of string: String) -> (text: String, marks: [Mark]) {
        var units = Array(string.utf16)
        var marks: [Mark] = []
        for (index, unit) in units.enumerated() {
            guard let kind = kind(of: unit) else { continue }
            units[index] = displayUnit(for: unit, kind: kind)
            marks.append(Mark(location: index, kind: kind))
        }
        guard !marks.isEmpty else { return (string, []) }
        return (String(utf16CodeUnits: units, count: units.count), marks)
    }

    /// The display form of an attributed paragraph, keeping the stylers'
    /// attributes and adding the faint mark; `nil` when nothing is marked,
    /// so the caller can let TextKit use the storage as is.
    static func displayParagraph(_ source: NSAttributedString) -> NSAttributedString? {
        let (text, marks) = displayForm(of: source.string)
        guard !marks.isEmpty else { return nil }

        let display = NSMutableAttributedString(attributedString: source)
        let units = text as NSString
        for mark in marks {
            // One unit at a time: a replacement takes the attributes of the
            // character it replaces, so the stylers' runs stay intact.
            let range = NSRange(location: mark.location, length: 1)
            display.replaceCharacters(in: range, with: units.substring(with: range))
            switch mark.kind {
            case .zeroWidth, .bidiControl, .unusualSpace:
                display.addAttribute(.backgroundColor, value: EditorTheme.invisibleCharacterColor, range: range)
            case .controlCode:
                display.addAttribute(.foregroundColor, value: EditorTheme.controlPictureColor, range: range)
            }
        }
        return display
    }
}

/// Substitutes marked characters in each paragraph TextKit lays out.
///
/// TextKit only asks for paragraphs it is about to lay out (viewport
/// driven) and again after each edit, so there is no document-wide scan
/// and no idle work (PRODUCT.md §29). Stateless, hence shared.
nonisolated final class InvisibleCharacterRevealer: NSObject, NSTextContentStorageDelegate {
    static let shared = InvisibleCharacterRevealer()

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard
            let storage = textContentStorage.textStorage,
            storage.mutableString.rangeOfCharacter(from: InvisibleCharacters.markedSet, options: [], range: range).location != NSNotFound,
            let display = InvisibleCharacters.displayParagraph(storage.attributedSubstring(from: range))
        else { return nil }
        return NSTextParagraph(attributedString: display)
    }
}

nonisolated extension EditorTheme {
    /// Faint tint behind a revealed zero-width, bidirectional, or unusual
    /// space character: visible on close reading, quiet otherwise.
    static let invisibleCharacterColor: NSColor = NSColor(name: nil) { appearance in
        NSColor.systemOrange.withAlphaComponent(
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.35 : 0.25
        )
    }

    /// Control Pictures (␀, ␛, …) recede like Markdown markers.
    static var controlPictureColor: NSColor { .tertiaryLabelColor }
}
