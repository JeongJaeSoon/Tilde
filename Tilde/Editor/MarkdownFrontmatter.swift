//
//  MarkdownFrontmatter.swift
//  Tilde
//

import Foundation

/// Detects the leading YAML frontmatter block (Jekyll / Hugo / Obsidian):
/// line 1 is `---`, closed by the next line that is `---` or `...`, and the
/// lines between are empty or include at least one top-level `key:` line.
///
/// The lines between are never parsed as YAML; the `key:` check only keeps
/// a document that opens with a `---` rule and has another rule further
/// down from losing everything in between. Anything that fails a check
/// stays ordinary Markdown. Fence lines may carry trailing spaces or tabs
/// (and a `\r`, for text that was not LF-normalized).
nonisolated enum MarkdownFrontmatter {

    /// The whole block, from offset 0 through the closing fence line
    /// (including its newline), or nil when the text has no frontmatter.
    static func range(in string: NSString) -> NSRange? {
        candidate(in: string).flatMap { isMetadata($0, in: string) ? $0 : nil }
    }

    /// Line 1 through the first closing fence, before the `key:` check.
    static func candidate(in string: NSString) -> NSRange? {
        guard let opening = openingLine(in: string) else { return nil }
        let rest = NSRange(location: NSMaxRange(opening), length: string.length - NSMaxRange(opening))
        return closingLine(in: string, within: rest).map { NSRange(location: 0, length: NSMaxRange($0)) }
    }

    /// Whether the lines between a candidate's fences read as metadata:
    /// all blank, or at least one top-level `key:` line.
    static func isMetadata(_ candidate: NSRange, in string: NSString) -> Bool {
        let opening = string.lineRange(for: NSRange(location: 0, length: 0))
        let closing = string.lineRange(for: NSRange(location: NSMaxRange(candidate) - 1, length: 0))
        let body = NSRange(location: NSMaxRange(opening), length: max(0, closing.location - NSMaxRange(opening)))
        if string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: body).location == NSNotFound {
            return true
        }
        return keyLine.firstMatch(in: string as String, range: body) != nil
    }

    /// A top-level YAML `key:` — plain or quoted, at column 0, followed by
    /// a space or the end of the line. Headings and ordinary sentences never
    /// match; a prose line such as `Note: …` does, which is the accepted
    /// cost of a check that stops short of parsing YAML.
    private static let keyLine = try! NSRegularExpression(
        pattern: "^(?:[\\w.$-]+|\"[^\"\r\n]*\"|'[^'\r\n]*')[ \t]*:(?:[ \t\r]|$)",
        options: .anchorsMatchLines
    )

    /// Line 1, when it is a `---` fence followed by at least one more line.
    static func openingLine(in string: NSString) -> NSRange? {
        // Cheap reject before lineRange: a document starting with `-` (a
        // list, say) would otherwise scan its whole first line per keystroke.
        guard string.length > 3,
              string.character(at: 0) == dash,
              string.character(at: 1) == dash,
              string.character(at: 2) == dash
        else { return nil }
        let line = string.lineRange(for: NSRange(location: 0, length: 0))
        guard NSMaxRange(line) < string.length, isFence(line, in: string, marker: dash)
        else { return nil }
        return line
    }

    /// The first `---` or `...` fence line starting within `range`.
    static func closingLine(in string: NSString, within range: NSRange) -> NSRange? {
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let first = string.character(at: line.location)
            if first == dash || first == dot, isFence(line, in: string, marker: first) {
                return line
            }
            guard NSMaxRange(line) > location else { break }
            location = NSMaxRange(line)
        }
        return nil
    }

    private static let dash = unichar(UInt8(ascii: "-"))
    private static let dot = unichar(UInt8(ascii: "."))

    /// Exactly three `marker` characters, then only trailing whitespace.
    private static func isFence(_ line: NSRange, in string: NSString, marker: unichar) -> Bool {
        guard line.length >= 3 else { return false }
        for offset in 0..<3 where string.character(at: line.location + offset) != marker {
            return false
        }
        for offset in 3..<line.length {
            switch string.character(at: line.location + offset) {
            case 0x20, 0x09, 0x0D, 0x0A: continue
            default: return false
            }
        }
        return true
    }
}
