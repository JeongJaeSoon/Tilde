//
//  LineEnding.swift
//  Tilde
//

import Foundation

/// Line-ending style of a document.
///
/// The in-memory buffer is always LF-normalized; the original style is
/// detected on load and restored on save.
nonisolated enum LineEnding: String {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    /// Detects the dominant line ending and returns the string normalized to LF.
    ///
    /// With `recordingMixed`, a string that mixes styles also returns the
    /// ending of every line (`nil` for uniform strings), so the save path
    /// can put them back on the lines the user didn't touch.
    static func normalizeToLF(
        _ string: String,
        recordingMixed: Bool = false
    ) -> (text: String, lineEnding: LineEnding, mixed: MixedLineEndings?) {
        var lf = 0, crlf = 0, cr = 0
        forEachEnding(in: string) { ending in
            switch ending {
            case .lf: lf += 1
            case .crlf: crlf += 1
            case .cr: cr += 1
            }
        }

        guard crlf > 0 || cr > 0 else { return (string, .lf, nil) }

        let dominant: LineEnding
        if crlf >= lf && crlf >= cr {
            dominant = .crlf
        } else if cr > lf {
            dominant = .cr
        } else {
            dominant = .lf
        }

        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let styles = [lf, crlf, cr].filter { $0 > 0 }.count
        guard recordingMixed, styles > 1 else { return (normalized, dominant, nil) }

        // Only mixed files pay for the second pass and the array.
        var endings: [LineEnding] = []
        endings.reserveCapacity(lf + crlf + cr)
        forEachEnding(in: string) { endings.append($0) }
        return (normalized, dominant, MixedLineEndings(text: normalized, endings: endings))
    }

    /// Restores this line ending in an LF-normalized string for saving.
    func restore(in string: String) -> String {
        guard self != .lf else { return string }
        return string.replacingOccurrences(of: "\n", with: rawValue)
    }

    /// Calls `body` with each line ending in `string`, in order.
    private static func forEachEnding(in string: String, _ body: (LineEnding) -> Void) {
        let scalars = string.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            switch scalars[index] {
            case "\r":
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    body(.crlf)
                    index = scalars.index(after: next)
                    continue
                }
                body(.cr)
            case "\n":
                body(.lf)
            default:
                break
            }
            index = scalars.index(after: index)
        }
    }
}

/// The per-line endings of a file that mixes styles, captured at load.
///
/// Saving gives each line whose text is unchanged since load its original
/// ending, and every new or edited line the dominant one, so changing one
/// line of a mixed file doesn't rewrite the endings of all the others.
/// A moved line counts as new.
nonisolated struct MixedLineEndings {
    /// The original text, LF-normalized.
    let text: String
    /// `endings[i]` is the ending after line `i` of `text`.
    let endings: [LineEnding]

    /// Above this many lines on either side of the changed middle (as after
    /// a replace-all across the file), the middle skips the diff and takes
    /// the dominant ending: Myers is O((N+M)·D), and the save must not stall.
    static let diffLimit = 5_000

    /// Restores line endings in an LF-normalized snapshot for saving.
    func restore(in snapshot: String, dominant: LineEnding) -> String {
        let old = text.split(separator: "\n", omittingEmptySubsequences: false)
        let new = snapshot.split(separator: "\n", omittingEmptySubsequences: false)

        // A typical edit leaves a long common prefix and suffix; only the
        // few lines between them need the diff.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        // For each line of the snapshot, the original line it still is.
        var origin = [Int?](repeating: nil, count: new.count)
        for i in 0..<prefix { origin[i] = i }
        for i in 0..<suffix { origin[new.count - 1 - i] = old.count - 1 - i }

        let oldMiddle = old[prefix..<(old.count - suffix)]
        let newMiddle = new[prefix..<(new.count - suffix)]
        if oldMiddle.count <= Self.diffLimit, newMiddle.count <= Self.diffLimit {
            // Diff integer IDs, not strings: equal lines share an ID, and
            // comparing Ints keeps the diff's inner loop cheap.
            var ids: [Substring: Int] = [:]
            func id(_ line: Substring) -> Int {
                if let id = ids[line] { return id }
                ids[line] = ids.count
                return ids.count - 1
            }
            let oldIDs = oldMiddle.map(id)
            let newIDs = newMiddle.map(id)
            var removed = Set<Int>(), inserted = Set<Int>()
            for change in newIDs.difference(from: oldIDs) {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            // The lines the diff kept pair up in order.
            var o = 0
            for n in 0..<newMiddle.count where !inserted.contains(n) {
                while removed.contains(o) { o += 1 }
                origin[prefix + n] = prefix + o
                o += 1
            }
        }

        // Every line but the last is followed by an ending, so a last line
        // without one never gains one. The original last line has no
        // recorded ending either; moved up, it takes the dominant one.
        var result = ""
        result.reserveCapacity(snapshot.utf8.count + new.count)
        for (i, line) in new.enumerated() {
            result.append(contentsOf: line)
            guard i < new.count - 1 else { break }
            if let j = origin[i], j < endings.count {
                result.append(endings[j].rawValue)
            } else {
                result.append(dominant.rawValue)
            }
        }
        return result
    }
}
