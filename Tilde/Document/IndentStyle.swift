//
//  IndentStyle.swift
//  Tilde
//

import Foundation

/// How a document is indented: what Tab inserts and ⇧Tab removes.
///
/// Detected once from the file's leading whitespace when it opens, the
/// way VS Code's "Detect Indentation" does, so Tab follows the file
/// instead of mixing a tab into space-indented text (#18).
nonisolated enum IndentStyle: Equatable {
    case tabs
    /// Spaces, with the indentation unit (1–8).
    case spaces(Int)

    /// Lines sampled for detection; the head of a file is representative,
    /// and a huge file shouldn't be walked to the end at load.
    static let sampleLineLimit = 1_000

    /// Reads the leading whitespace of the first `sampleLineLimit`
    /// non-blank lines. Tab-led lines outnumbering space-led ones means
    /// tabs; otherwise the unit is the most common positive step between
    /// consecutive space-indented lines. `nil` when no line is indented.
    static func detect(in text: String) -> IndentStyle? {
        var tabLed = 0, spaceLed = 0
        var stepCounts = [Int](repeating: 0, count: 9)
        // Indentation of the previous non-blank line, in spaces; `nil` when
        // it contained a tab, so no step is measured across it.
        var previous: Int? = 0
        var sampled = 0

        // The current line's leading whitespace.
        var first: UInt8 = 0, spaces = 0, hasTab = false
        var atLineStart = true, isBlank = true
        func endLine() {
            defer { first = 0; spaces = 0; hasTab = false; atLineStart = true; isBlank = true }
            guard !isBlank else { return }
            sampled += 1
            if first == 0x09 { tabLed += 1 } else if first == 0x20 { spaceLed += 1 }
            let current: Int? = hasTab ? nil : spaces
            if let current, let previous {
                let step = abs(current - previous)
                if step <= 8 { stepCounts[step] += 1 }
            }
            previous = current
        }

        for byte in text.utf8 {
            if byte == 0x0A {
                endLine()
                if sampled >= sampleLineLimit { break }
                continue
            }
            guard atLineStart else { continue }
            switch byte {
            case 0x20, 0x09:
                if first == 0 { first = byte }
                if byte == 0x09 { hasTab = true } else { spaces += 1 }
            case 0x0D:
                break
            default:
                atLineStart = false
                isBlank = false
            }
        }
        if sampled < sampleLineLimit { endLine() }

        if tabLed > spaceLed { return .tabs }
        guard spaceLed > 0 else { return nil }
        // Most common step; a tie goes to the smaller unit.
        var unit = 0
        for step in 1...8 where unit == 0 ? stepCounts[step] > 0 : stepCounts[step] > stepCounts[unit] {
            unit = step
        }
        return unit == 0 ? nil : .spaces(unit)
    }

    /// The style Tab uses for a document. YAML forbids tabs in indentation,
    /// so it always gets spaces (the detected unit, or 2). Other files
    /// follow what was detected; with no evidence Tab keeps inserting a
    /// tab character, as before detection existed.
    static func effective(detected: IndentStyle?, fileExtension: String?) -> IndentStyle {
        switch fileExtension?.lowercased() {
        case "yaml", "yml":
            if case .spaces(let unit)? = detected { return .spaces(unit) }
            return .spaces(2)
        default:
            return detected ?? .tabs
        }
    }

    // MARK: - Edits

    /// One replacement in the buffer, and the selection to set after it.
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    /// Columns per level: the space unit, or the tab width Tilde assumes
    /// when measuring tabs and outdenting space-indented lines in a
    /// tab-indented file.
    var width: Int {
        switch self {
        case .tabs: return 4
        case .spaces(let unit): return max(1, unit)
        }
    }

    /// One level of indentation, as inserted at the start of a line.
    var unit: String {
        switch self {
        case .tabs: return "\t"
        case .spaces: return String(repeating: " ", count: width)
        }
    }

    /// Tab. A selection within one line is replaced by one level — for
    /// spaces, enough to reach the next multiple of the unit counted from
    /// the line start, like a tab stop. A selection spanning lines indents
    /// every line it touches by one level, skipping empty lines, and grows
    /// to keep covering the same text.
    func indent(in text: NSString, selection: NSRange) -> Edit {
        guard text.substring(with: selection).contains("\n") else {
            let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
            let insertion: String
            switch self {
            case .tabs:
                insertion = "\t"
            case .spaces:
                let prefix = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
                let column = Self.column(after: prefix, tabWidth: width)
                insertion = String(repeating: " ", count: width - column % width)
            }
            let caret = selection.location + (insertion as NSString).length
            return Edit(range: selection, replacement: insertion, selection: NSRange(location: caret, length: 0))
        }
        return lineEdit(in: text, selection: selection) { line in
            line.isEmpty ? 0 : -(unit as NSString).length
        } transform: { line in
            line.isEmpty ? line : unit + line
        }
    }

    /// ⇧Tab. Removes one level — a leading tab, or up to `width` leading
    /// spaces — from the caret's line or every line the selection touches.
    /// `nil` when no touched line has leading whitespace.
    func outdent(in text: NSString, selection: NSRange) -> Edit? {
        let width = width
        func removal(_ line: String) -> Int {
            if line.hasPrefix("\t") { return 1 }
            return line.prefix(width).prefix { $0 == " " }.count
        }
        let edit = lineEdit(in: text, selection: selection, delta: removal) { line in
            String(line.dropFirst(removal(line)))
        }
        return edit.replacement == text.substring(with: edit.range) ? nil : edit
    }

    /// Rewrites each line the selection touches. `delta` is how many
    /// UTF-16 units a line loses at its start (negative: gains). A
    /// selection that ends at the start of a line doesn't touch it.
    private func lineEdit(
        in text: NSString,
        selection: NSRange,
        delta: (String) -> Int,
        transform: (String) -> String
    ) -> Edit {
        let start = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let last = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        var end = NSMaxRange(text.lineRange(for: NSRange(location: last, length: 0)))
        if end > start, text.character(at: end - 1) == 0x0A { end -= 1 }
        let block = NSRange(location: start, length: end - start)
        let lines = text.substring(with: block).components(separatedBy: "\n")

        // Each line's start in the original text and the units it loses.
        var shifts: [(start: Int, delta: Int)] = []
        var lineStart = start
        for line in lines {
            shifts.append((lineStart, delta(line)))
            lineStart += (line as NSString).length + 1
        }
        // A caret at a line's start stays there: an indented line's new
        // whitespace lands inside the selection, an outdented line's
        // removed whitespace was at or after the caret.
        func map(_ position: Int) -> Int {
            var mapped = position
            for shift in shifts where position > shift.start {
                mapped -= shift.delta < 0 ? shift.delta : min(position - shift.start, shift.delta)
            }
            return mapped
        }
        let newStart = map(selection.location)
        let newEnd = map(NSMaxRange(selection))
        return Edit(
            range: block,
            replacement: lines.map(transform).joined(separator: "\n"),
            selection: NSRange(location: newStart, length: newEnd - newStart)
        )
    }

    /// Display column after `prefix`, with tabs advancing to the next
    /// multiple of `tabWidth`.
    static func column(after prefix: String, tabWidth: Int) -> Int {
        var column = 0
        for unit in prefix.utf16 {
            column = unit == 0x09 ? (column / tabWidth + 1) * tabWidth : column + 1
        }
        return column
    }
}
