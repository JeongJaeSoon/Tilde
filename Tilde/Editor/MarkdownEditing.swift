//
//  MarkdownEditing.swift
//  Tilde
//

import Foundation

/// Pure text transforms behind the editor's Markdown editing commands:
/// wrapping the selection in a typed marker, ⌘B / ⌘I, and ⌘K.
///
/// Every function takes the buffer and the selection in UTF-16 offsets (the
/// text view's `NSRange`s) and returns one replacement, or `nil` when the
/// command doesn't apply. Each edit touches a single line only, like the
/// styler's inline rules.
nonisolated enum MarkdownEditing {
    struct Edit: Equatable {
        /// The range of the original text to replace.
        var range: NSRange
        var replacement: String
        /// The selection after the edit, in the edited text.
        var selection: NSRange
    }

    enum Emphasis {
        case bold, italic

        var markerLength: Int { self == .bold ? 2 : 1 }
    }

    /// Opening and closing markers for each character that wraps a selection.
    static let wrapPairs: [String: (open: String, close: String)] = [
        "*": ("*", "*"), "_": ("_", "_"), "`": ("`", "`"), "~": ("~", "~"),
        "[": ("[", "]"), "(": ("(", ")"), "\"": ("\"", "\""),
    ]

    // MARK: - Typed wrap

    /// Wraps the selection in the markers for `character`. The selection
    /// stays on the inner text, so a second `*` makes `**bold**`. Edge
    /// whitespace stays outside the markers — emphasis with a space just
    /// inside isn't emphasis.
    static func surround(_ text: NSString, selection: NSRange, with character: String) -> Edit? {
        guard let pair = wrapPairs[character],
              let inner = trimmedSingleLine(text, selection) else { return nil }
        let content = text.substring(with: inner)
        return Edit(
            range: inner,
            replacement: pair.open + content + pair.close,
            selection: NSRange(location: inner.location + pair.open.utf16.count, length: inner.length)
        )
    }

    // MARK: - Bold / italic

    /// Toggles `**` (bold) or `*` (italic) around the selection.
    ///
    /// Markers count when they sit just outside the selection or at its
    /// ends. The length of the `*` run beside the content decides what is
    /// present — 2 or 3 means bold, 1 or 3 means italic — so ⌘I inside
    /// `**x**` stacks to `***x***` instead of stripping one side of the bold.
    /// A line prefix (`#`, `>`, a list bullet or number, a task box) in the
    /// selection stays outside the markers, so a whole `* item` line becomes
    /// `* **item**`. An empty selection inserts the empty pair with the caret
    /// inside; a selection spanning lines (or only whitespace or a prefix)
    /// returns `nil`, and so does a core whose own `*` runs close the
    /// markers around it early.
    static func toggleEmphasis(_ emphasis: Emphasis, in text: NSString, selection: NSRange) -> Edit? {
        let m = emphasis.markerLength
        if selection.length == 0 {
            let pair = String(repeating: "*", count: m * 2)
            return Edit(range: selection, replacement: pair,
                        selection: NSRange(location: selection.location + m, length: 0))
        }
        guard var core = trimmedSingleLine(text, selection) else { return nil }
        let line = text.lineRange(for: core)

        let prefixEnd = line.location + linePrefixLength(text, line: line)
        if core.location < prefixEnd {
            guard prefixEnd < NSMaxRange(core),
                  let rest = trimmed(text, NSRange(location: prefixEnd, length: NSMaxRange(core) - prefixEnd))
            else { return nil }
            core = rest
        }

        // Markers selected along with the text: move them out of the core.
        let insideLeading = run(of: "*", in: text, from: core.location, upTo: NSMaxRange(core))
        let insideTrailing = runBackward(of: "*", in: text, from: NSMaxRange(core), downTo: core.location)
        if insideLeading + insideTrailing < core.length,
           let inner = trimmed(text, NSRange(location: core.location + insideLeading,
                                             length: core.length - insideLeading - insideTrailing)) {
            core = inner
        }

        let left = runBackward(of: "*", in: text, from: core.location, downTo: line.location)
        let right = run(of: "*", in: text, from: NSMaxRange(core), upTo: NSMaxRange(line))
        let markers = min(left, right)
        // `**one** and **two**`: the edge markers belong to two spans, not one around the core.
        if markers > 0, !innerRunsBalance(text, core) { return nil }

        let present: Bool
        switch emphasis {
        case .bold: present = markers == 2 || markers == 3
        case .italic: present = markers == 1 || markers == 3
        }
        let newMarkers = present ? markers - m : markers + m
        let stars = String(repeating: "*", count: newMarkers)
        return Edit(
            range: NSRange(location: core.location - markers, length: core.length + markers * 2),
            replacement: stars + text.substring(with: core) + stars,
            selection: NSRange(location: core.location - markers + newMarkers, length: core.length)
        )
    }

    // MARK: - Links

    /// Makes the selection a link to `url` (already from `linkableURL`), or
    /// a link with an empty destination when `url` is nil.
    ///
    /// The caret lands where typing continues: after the link when it is
    /// complete, inside `()` when the URL is missing, inside `[]` when there
    /// is no selection to be the text. A selection spanning lines (or only
    /// whitespace) returns `nil`.
    static func link(in text: NSString, selection: NSRange, url: String?) -> Edit? {
        let destination = url ?? ""
        let range: NSRange
        let label: String
        if selection.length == 0 {
            range = selection
            label = ""
        } else {
            guard let inner = trimmedSingleLine(text, selection) else { return nil }
            range = inner
            label = text.substring(with: inner)
        }
        let replacement = "[\(label)](\(destination))"
        let caret: Int
        if label.isEmpty {
            caret = range.location + 1
        } else if url == nil {
            caret = range.location + replacement.utf16.count - 1
        } else {
            caret = range.location + replacement.utf16.count
        }
        return Edit(range: range, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// The clipboard text as a link destination when it is exactly one
    /// `http`, `https`, or `mailto` URL once surrounding whitespace is
    /// trimmed; `nil` otherwise. Parentheses are percent-encoded so the
    /// destination can't close the link early in the styler or Reader.
    static func linkableURL(from string: String) -> String? {
        let candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else { return nil }
        case "mailto":
            guard candidate.count > "mailto:".count else { return nil }
        default:
            return nil
        }
        return candidate
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    // MARK: - Helpers

    /// The selection minus edge spaces and tabs, or `nil` when it is empty,
    /// only whitespace, or spans lines.
    private static func trimmedSingleLine(_ text: NSString, _ selection: NSRange) -> NSRange? {
        guard selection.length > 0, NSMaxRange(selection) <= text.length else { return nil }
        let selected = text.substring(with: selection)
        guard selected.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return trimmed(text, selection)
    }

    private static func trimmed(_ text: NSString, _ range: NSRange) -> NSRange? {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isBlank(text.character(at: start)) { start += 1 }
        while end > start, isBlank(text.character(at: end - 1)) { end -= 1 }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// Block markers at the start of a line: indentation, `>` quotes, then
    /// one heading, list bullet / number, or bullet with a task box.
    private static let linePrefix = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:>[ \t]*)*(?:#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d{1,9}[.)][ \t]+)?"#
    )

    private static func linePrefixLength(_ text: NSString, line: NSRange) -> Int {
        let lineText = text.substring(with: line)
        return linePrefix.firstMatch(in: lineText, options: .anchored,
                                     range: NSRange(location: 0, length: (lineText as NSString).length))?.range.length ?? 0
    }

    /// Whether every `*` run in `range` that opens a span is closed by a
    /// later one. A run counts as opening when text follows it and a blank,
    /// punctuation, or the range start comes before; closing is the mirror.
    /// Intraword runs (`a**b`) and runs between blanks (`2 * 3`) don't count.
    private static func innerRunsBalance(_ text: NSString, _ range: NSRange) -> Bool {
        let star = Character("*").utf16.first!
        func isBoundary(_ i: Int) -> Bool {
            guard i >= range.location, i < NSMaxRange(range) else { return true }
            let unit = text.character(at: i)
            return isBlank(unit) || (unit < 0x80 && ispunct(Int32(unit)) != 0)
        }
        var open = 0
        var i = range.location
        while i < NSMaxRange(range) {
            guard text.character(at: i) == star else { i += 1; continue }
            let length = run(of: "*", in: text, from: i, upTo: NSMaxRange(range))
            let before = i - 1, after = i + length
            let opens = !isBoundary(after) && isBoundary(before)
            let closes = !isBoundary(before) && isBoundary(after)
            if opens { open += 1 } else if closes {
                if open == 0 { return false }
                open -= 1
            }
            i = after
        }
        return open == 0
    }

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x3000
    }

    private static func run(of marker: Character, in text: NSString, from start: Int, upTo limit: Int) -> Int {
        let unit = marker.utf16.first!
        var i = start
        while i < limit, text.character(at: i) == unit { i += 1 }
        return i - start
    }

    private static func runBackward(of marker: Character, in text: NSString, from end: Int, downTo limit: Int) -> Int {
        let unit = marker.utf16.first!
        var i = end
        while i > limit, text.character(at: i - 1) == unit { i -= 1 }
        return end - i
    }
}
