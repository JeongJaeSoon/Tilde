//
//  MarkdownStyler+Links.swift
//  Tilde
//

import Foundation

/// What the editor's ⌘-click needs from the styled buffer: which link sits
/// under a character, and which line a `#fragment` names.
extension MarkdownStyler {
    /// Marks each `[text](url)` the styler tinted — brackets and URL
    /// included — with its raw `(…)` target. Images, code, and frontmatter
    /// never carry it, and since every restyle resets the attributes, a
    /// buffer without Markdown styling carries none at all.
    static let linkTargetKey = NSAttributedString.Key("tildeLinkTarget")

    /// The raw target of the styled link covering `index`, if any.
    static func linkTarget(at index: Int, in text: NSAttributedString) -> String? {
        guard index >= 0, index < text.length else { return nil }
        return text.attribute(linkTargetKey, at: index, effectiveRange: nil) as? String
    }

    private static let atxHeadingPattern = try! NSRegularExpression(pattern: "^ {0,3}#{1,6}(?:[ \\t]+|$)")
    private static let fencePattern = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})")

    /// Where the `#fragment` heading starts in `string`: ATX headings
    /// outside fenced code and frontmatter are slugged in order, duplicates
    /// taking GitHub's `-1`, `-2`… suffixes as in Reader, and the first
    /// whose slug matches wins.
    static func headingLocation(forFragment fragment: String, in string: NSString) -> Int? {
        let target = MarkdownLink.anchorSlug(forFragment: fragment)
        let bodyStart = MarkdownFrontmatter.range(in: string).map(NSMaxRange) ?? 0

        var used: Set<String> = []
        // The styler only knows column-0 ``` fences; here a `# comment` in a
        // `~~~` or list-indented fence would shift every later slug.
        var openFence: String?
        var location = bodyStart
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            defer { location = NSMaxRange(line) }

            let lineText = string.substring(with: line).trimmingCharacters(in: .newlines)
            let whole = NSRange(location: 0, length: (lineText as NSString).length)
            if let fence = fencePattern.firstMatch(in: lineText, range: whole) {
                let run = (lineText as NSString).substring(with: fence.range(at: 1))
                let rest = (lineText as NSString).substring(from: NSMaxRange(fence.range))
                if let open = openFence {
                    if run.first == open.first, run.count >= open.count,
                       rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        openFence = nil
                    }
                    continue
                } else if !(run.first == "`" && rest.contains("`")) {
                    // A backtick info string can't hold a backtick: that's a code span.
                    openFence = run
                    continue
                }
            }
            if openFence != nil { continue }

            guard atxHeadingPattern.firstMatch(in: lineText, range: whole) != nil else { continue }
            let slug = MarkdownLink.uniqueAnchor(MarkdownLink.anchorSlug(for: headingText(lineText)), used: &used)
            if slug == target { return line.location }
        }
        return nil
    }

    /// The heading's text as Reader slugs it: parsed with Reader's options,
    /// so closing `#`s, links, emphasis, and entities resolve the same way.
    private static func headingText(_ line: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: line, options: options) else { return line }
        return String(parsed.characters)
    }
}
