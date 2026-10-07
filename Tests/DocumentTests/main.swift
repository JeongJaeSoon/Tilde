// Tests for Tilde's document layer: FileEncoding, LineEnding, and the
// document-type decision. Compiled as a plain executable by Tests/run.sh —
// no XCTest, so the suite runs on machines with only the Command Line Tools.

import Foundation

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("  ok  \(name)") }
    else { failed += 1; print("FAIL  \(name)") }
}

// MARK: - FileEncoding

// UTF-8 roundtrip
do {
    let original = "Hello, 世界! 한글 テキスト\n"
    let data = Data(original.utf8)
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == original, "utf8 decode")
    expect(decoded.encoding == FileEncoding(base: .utf8, hasBOM: false), "utf8 detected without BOM")
    expect(decoded.encoding.encode(decoded.string) == data, "utf8 roundtrip is byte-identical")
    expect(!decoded.isLossy, "utf8 decode is not lossy")
}

// UTF-8 with BOM preserved
do {
    var data = Data([0xEF, 0xBB, 0xBF])
    data.append(Data("bom test".utf8))
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == "bom test", "utf8 BOM stripped from text")
    expect(decoded.encoding.hasBOM, "utf8 BOM detected")
    expect(decoded.encoding.encode(decoded.string) == data, "utf8 BOM roundtrip is byte-identical")
}

// UTF-16 LE with BOM
do {
    let original = "utf16 little endian ✓"
    var data = Data([0xFF, 0xFE])
    data.append(original.data(using: .utf16LittleEndian)!)
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == original, "utf16le decode")
    expect(decoded.encoding == FileEncoding(base: .utf16LittleEndian, hasBOM: true), "utf16le BOM detected")
    expect(decoded.encoding.encode(decoded.string) == data, "utf16le roundtrip is byte-identical")
}

// UTF-16 BE with BOM
do {
    let original = "utf16 big endian ✓"
    var data = Data([0xFE, 0xFF])
    data.append(original.data(using: .utf16BigEndian)!)
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == original, "utf16be decode")
    expect(decoded.encoding == FileEncoding(base: .utf16BigEndian, hasBOM: true), "utf16be BOM detected")
    expect(decoded.encoding.encode(decoded.string) == data, "utf16be roundtrip is byte-identical")
}

// UTF-16 LE without BOM: the NUL-alternation heuristic must catch it
// BEFORE the UTF-8 pass (NUL bytes are valid UTF-8 — the bug this suite
// originally caught).
do {
    let original = "plain ascii text for the heuristic to chew on"
    let data = original.data(using: .utf16LittleEndian)!
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == original, "utf16le no-BOM heuristic decode")
    expect(decoded.encoding == FileEncoding(base: .utf16LittleEndian, hasBOM: false), "utf16le no-BOM detected")
    expect(decoded.encoding.encode(decoded.string) == data, "utf16le no-BOM roundtrip adds no BOM")
}

// UTF-16 BE without BOM
do {
    let original = "big endian without a byte order mark"
    let data = original.data(using: .utf16BigEndian)!
    let decoded = FileEncoding.decode(data)
    expect(decoded.string == original, "utf16be no-BOM heuristic decode")
    expect(decoded.encoding == FileEncoding(base: .utf16BigEndian, hasBOM: false), "utf16be no-BOM detected")
}

// Invalid bytes never fail to open — but MUST be flagged lossy, because
// re-encoding the substituted text would corrupt the original file
// (2026-08 app review P1: the document layer blocks saving lossy documents).
do {
    let data = Data([0x48, 0x69, 0xFF, 0xFE, 0x00, 0xD8, 0x41])
    let decoded = FileEncoding.decode(data)
    expect(!decoded.string.isEmpty, "invalid bytes still decode (lossy)")
    expect(decoded.isLossy, "invalid bytes flagged lossy")
    expect(decoded.encoding.encode(decoded.string) != data,
           "lossy roundtrip is NOT byte-identical (why saving is blocked)")
}

// BOM-less UTF-16 Korean text: no NUL bytes for the alternation heuristic
// to catch, and the byte pairs are invalid UTF-8 — the decode falls to the
// lossy path and must say so instead of silently mangling the file.
do {
    let data = "안녕하세요세계".data(using: .utf16LittleEndian)!
    let decoded = FileEncoding.decode(data)
    expect(decoded.isLossy, "BOM-less utf16 Korean flagged lossy")
    expect(decoded.encoding.encode(decoded.string) != data,
           "BOM-less utf16 Korean cannot round-trip")
}

// Odd-length UTF-16 with BOM (file truncated mid-code-unit): Foundation's
// UTF-16 decoder silently DROPS the trailing byte instead of failing, so
// without the even-length guard this decoded as non-lossy and saving
// destroyed the final byte. Must be flagged lossy.
do {
    var le = Data([0xFF, 0xFE])
    le.append("Hello".data(using: .utf16LittleEndian)!)
    le.removeLast()   // truncate mid-code-unit
    let decodedLE = FileEncoding.decode(le)
    expect(decodedLE.isLossy, "odd-length BOM'd utf16le flagged lossy")

    var be = Data([0xFE, 0xFF])
    be.append("Hello".data(using: .utf16BigEndian)!)
    be.removeLast()
    let decodedBE = FileEncoding.decode(be)
    expect(decodedBE.isLossy, "odd-length BOM'd utf16be flagged lossy")
}

// A lone surrogate in BOM'd UTF-16 makes the strict decoder fail → lossy.
do {
    let data = Data([0xFF, 0xFE, 0x00, 0xD8, 0x41, 0x00])
    let decoded = FileEncoding.decode(data)
    expect(decoded.isLossy, "lone surrogate utf16 flagged lossy")
}

// Legacy encoding outside the detection list (EUC-KR "안녕하세요"):
// opens lossily, flagged so it can never be saved over the original.
do {
    let data = Data([0xBE, 0xC8, 0xB3, 0xE7, 0xC7, 0xCF, 0xBC, 0xBC, 0xBF, 0xE4])
    let decoded = FileEncoding.decode(data)
    expect(!decoded.string.isEmpty, "EUC-KR bytes still open")
    expect(decoded.isLossy, "EUC-KR flagged lossy")
}

// Every non-lossy detection path must round-trip byte-identically AND
// report not-lossy — the pair of guarantees the save path relies on.
do {
    var samples: [Data] = [
        Data("plain ascii\n".utf8),
        Data([0xEF, 0xBB, 0xBF]) + Data("bom utf8".utf8),
        Data([0xFF, 0xFE]) + "utf16le ✓".data(using: .utf16LittleEndian)!,
        Data([0xFE, 0xFF]) + "utf16be ✓".data(using: .utf16BigEndian)!,
        "ascii heuristic text".data(using: .utf16LittleEndian)!,
        "ascii heuristic text".data(using: .utf16BigEndian)!,
    ]
    samples.append(Data("emoji 🌊 and 한글\n".utf8))
    let allFaithful = samples.allSatisfy { data in
        let decoded = FileEncoding.decode(data)
        return !decoded.isLossy && decoded.encoding.encode(decoded.string) == data
    }
    expect(allFaithful, "all non-lossy paths round-trip byte-identically")
}

// Empty file
do {
    let decoded = FileEncoding.decode(Data())
    expect(decoded.string.isEmpty, "empty file decodes to empty string")
    expect(decoded.encoding == .default, "empty file gets default encoding")
    expect(!decoded.isLossy, "empty file is not lossy")
}

// MARK: - LineEnding

// LF stays untouched
do {
    let result = LineEnding.normalizeToLF("a\nb\nc\n")
    expect(result.text == "a\nb\nc\n", "lf text unchanged")
    expect(result.lineEnding == .lf, "lf detected")
}

// CRLF detected, normalized, restored
do {
    let original = "a\r\nb\r\nc\r\n"
    let result = LineEnding.normalizeToLF(original)
    expect(result.text == "a\nb\nc\n", "crlf normalized to lf")
    expect(result.lineEnding == .crlf, "crlf detected")
    expect(result.lineEnding.restore(in: result.text) == original, "crlf restored byte-identical")
}

// Classic Mac CR
do {
    let original = "a\rb\rc"
    let result = LineEnding.normalizeToLF(original)
    expect(result.text == "a\nb\nc", "cr normalized to lf")
    expect(result.lineEnding == .cr, "cr detected")
    expect(result.lineEnding.restore(in: result.text) == original, "cr restored byte-identical")
}

// Mixed: dominant wins
do {
    let result = LineEnding.normalizeToLF("a\r\nb\r\nc\r\nd\ne\r\n")
    expect(result.lineEnding == .crlf, "dominant crlf wins in mixed file")
    expect(result.text == "a\nb\nc\nd\ne\n", "mixed file fully normalized")
}

// No line endings at all
do {
    let result = LineEnding.normalizeToLF("single line")
    expect(result.text == "single line", "single line unchanged")
    expect(result.lineEnding == .lf, "no EOL defaults to lf")
}

// Empty string
do {
    let result = LineEnding.normalizeToLF("")
    expect(result.text == "" && result.lineEnding == .lf, "empty string defaults")
}

// MARK: - Mixed line endings keep untouched lines' endings (issue #17)

/// Loads `original` the way `TextDocument` does, applies `edit` to the
/// LF-normalized buffer, and returns what saving would write.
func saved(_ original: String, _ edit: (String) -> String = { $0 }) -> String {
    let loaded = LineEnding.normalizeToLF(original, recordingMixed: true)
    let snapshot = LineEnding.normalizeToLF(edit(loaded.text)).text
    return loaded.mixed?.restore(in: snapshot, dominant: loaded.lineEnding)
        ?? loaded.lineEnding.restore(in: snapshot)
}

// Uniform files record nothing, so they pay nothing.
do {
    expect(LineEnding.normalizeToLF("a\r\nb\r\n", recordingMixed: true).mixed == nil,
           "uniform crlf records no mixed endings")
    expect(LineEnding.normalizeToLF("a\nb\n", recordingMixed: true).mixed == nil,
           "uniform lf records no mixed endings")
    expect(LineEnding.normalizeToLF("a\r\nb\nc\r\n").mixed == nil,
           "mixed endings recorded only when asked (paste path)")
    let mixed = LineEnding.normalizeToLF("a\r\nb\nc\r", recordingMixed: true).mixed
    expect(mixed?.endings == [.crlf, .lf, .cr], "mixed endings recorded in order")
}

// No edits (autosave, Save As, Duplicate): byte-identical.
do {
    let samples = [
        "a\r\nb\r\nc\r\nd\ne\r\n",
        "a\nb\r\nc\rd\n",
        "a\r\nb\nno newline at end",
        "\r\n\n\r\n\n",
        "x\r\ny\n\n\r\n",
    ]
    expect(samples.allSatisfy { saved($0) == $0 }, "unedited mixed file saves byte-identically")
}

// The issue's repro: editing line 1 leaves line d's LF alone.
do {
    let result = saved("a\r\nb\r\nc\r\nd\ne\r\n") { $0.replacingOccurrences(of: "a\n", with: "A\n") }
    expect(result == "A\r\nb\r\nc\r\nd\ne\r\n", "editing one line keeps the others' endings")
}

// An edited line takes the dominant ending, even if it was LF before.
do {
    let result = saved("a\r\nb\nc\r\nd\r\n") { $0.replacingOccurrences(of: "b\n", with: "B\n") }
    expect(result == "a\r\nB\r\nc\r\nd\r\n", "edited line takes the dominant ending")
}

// An inserted line takes the dominant ending.
do {
    let result = saved("a\r\nb\nc\r\nd\r\n") { $0.replacingOccurrences(of: "b\n", with: "b\nnew\n") }
    expect(result == "a\r\nb\nnew\r\nc\r\nd\r\n", "inserted line takes the dominant ending")
}

// Deleting a line leaves its neighbours' endings alone.
do {
    let result = saved("a\r\nb\nc\r\nd\ne\r\n") { $0.replacingOccurrences(of: "c\n", with: "") }
    expect(result == "a\r\nb\nd\ne\r\n", "deleting a line keeps its neighbours' endings")
}

// Several separate edits: untouched lines between them keep theirs.
do {
    let result = saved("1\r\n2\n3\r\n4\n5\r\n6\n7\r\n") { text in
        text.replacingOccurrences(of: "2\n", with: "two\n")
            .replacingOccurrences(of: "6\n", with: "six\n")
    }
    expect(result == "1\r\ntwo\r\n3\r\n4\n5\r\nsix\r\n7\r\n", "untouched lines between edits keep their endings")
}

// Identical lines are interchangeable: the one the pairing calls new
// takes the dominant ending, and the originals keep theirs in order.
do {
    let result = saved("x\r\nx\nx\r\nx\n") { "x\n" + $0 }
    expect(result == "x\r\nx\nx\r\nx\nx\r\n", "inserting a duplicate line keeps the existing endings in order")
}

// A CR line in the mix survives an edit elsewhere; a CR-dominant file
// gives the edited line CR.
do {
    let result = saved("a\r\nb\rc\r\nd\r\n") { $0.replacingOccurrences(of: "d\n", with: "D\n") }
    expect(result == "a\r\nb\rc\r\nD\r\n", "cr line survives an edit elsewhere")
    let crDominant = saved("a\rb\rc\nd\r") { $0.replacingOccurrences(of: "a\n", with: "A\n") }
    expect(crDominant == "A\rb\rc\nd\r", "cr-dominant file gives the edited line cr")
}

// A last line without a newline never gains one; a line typed after it
// makes the old last line end with the dominant ending.
do {
    let edited = saved("a\r\nb\nc") { $0.replacingOccurrences(of: "c", with: "C") }
    expect(edited == "a\r\nb\nC", "edited last line gains no newline")
    let appended = saved("a\r\nb\nc") { $0 + "\nd" }
    expect(appended == "a\r\nb\nc\r\nd", "line after the old last line: dominant ending, still none at end")
    let newline = saved("a\r\nb\nc") { $0 + "\n" }
    expect(newline == "a\r\nb\nc\r\n", "newline typed at the end takes the dominant ending")
}

// Moving a line counts as new: it takes the dominant ending.
do {
    let result = saved("a\r\nm\nb\r\nc\r\nd\r\n") { _ in "a\nb\nc\nd\nm\n" }
    expect(result == "a\r\nb\r\nc\r\nd\r\nm\r\n", "moved line takes the dominant ending")
}

// Everything deleted, or everything replaced.
do {
    expect(saved("a\r\nb\n") { _ in "" } == "", "emptied mixed file saves empty")
    expect(saved("a\r\nb\nc\r\n") { _ in "x\ny\n" } == "x\r\ny\r\n", "fully replaced file takes the dominant ending")
}

// A middle past the diff limit skips the diff and takes the dominant ending.
do {
    let n = MixedLineEndings.diffLimit + 1
    var original = "head\n"
    for i in 0..<n { original += "line \(i)" + (i == 0 ? "\n" : "\r\n") }
    original += "tail\n"
    let result = saved(original) { $0.replacingOccurrences(of: "line", with: "LINE") }
    expect(result.hasPrefix("head\nLINE 0\r\nLINE 1\r\n"), "large middle falls back to the dominant ending")
    expect(result.hasSuffix("\r\ntail\n"), "large middle keeps the untouched prefix and suffix endings")
}

// A large but local edit stays fast: prefix/suffix trimming leaves a tiny middle.
do {
    var original = ""
    for i in 0..<200_000 { original += "line \(i)" + (i % 7 == 0 ? "\n" : "\r\n") }
    let start = Date()
    let edited = saved(original) { text in
        var lines = text.components(separatedBy: "\n")
        lines[100_000] = "edited"
        return lines.joined(separator: "\n")
    }
    let elapsed = Date().timeIntervalSince(start)
    let expected = original.replacingOccurrences(of: "line 100000\r\n", with: "edited\r\n")
    expect(edited == expected, "one edit in a 200k-line mixed file changes only that line")
    expect(elapsed < 2, "200k-line mixed save stays fast (\(String(format: "%.2f", elapsed))s)")
}

// Worst case under the limit: every middle line replaced on both sides.
do {
    let n = MixedLineEndings.diffLimit
    var original = ""
    for i in 0..<n { original += "old \(i)" + (i.isMultiple(of: 2) ? "\n" : "\r\n") }
    let start = Date()
    let result = saved(original) { $0.replacingOccurrences(of: "old", with: "new") }
    let elapsed = Date().timeIntervalSince(start)
    expect(!result.contains("\n\n") && result.hasSuffix("\r\n"), "full rewrite under the limit saves")
    print("      full rewrite of \(n) lines: \(String(format: "%.2f", elapsed))s")
}

// MARK: - Markdown-ness follows the live extension (2026-08 app review P2)

// A document opened as Markdown then saved as .txt/.json must LEAVE
// Markdown mode, and the reverse switch must work too; the open-time type
// only decides for extension-less files and untitled documents.
do {
    let md = URL(fileURLWithPath: "/tmp/a.md")
    let txt = URL(fileURLWithPath: "/tmp/a.txt")
    let json = URL(fileURLWithPath: "/tmp/a.json")
    let bare = URL(fileURLWithPath: "/tmp/README")
    expect(TextDocument.isMarkdown(openedAsMarkdown: true, fileURL: txt) == false,
           "markdown saved as .txt leaves markdown mode")
    expect(TextDocument.isMarkdown(openedAsMarkdown: true, fileURL: json) == false,
           "markdown saved as .json leaves markdown mode")
    expect(TextDocument.isMarkdown(openedAsMarkdown: false, fileURL: md) == true,
           "text saved as .md enters markdown mode")
    expect(TextDocument.isMarkdown(openedAsMarkdown: true, fileURL: bare) == true,
           "extension-less file keeps its opened type")
    expect(TextDocument.isMarkdown(openedAsMarkdown: false, fileURL: bare) == false,
           "extension-less plain file stays plain")
    expect(TextDocument.isMarkdown(openedAsMarkdown: false, fileURL: nil) == false,
           "untitled document defaults to plain")
    expect(TextDocument.isMarkdown(openedAsMarkdown: true,
                                   fileURL: URL(fileURLWithPath: "/tmp/b.MARKDOWN")) == true,
           "markdown extension match is case-insensitive")
}

// MARK: - Indentation follows the file (#18)

do {
    expect(IndentStyle.detect(in: "a\n\tb\n\t\tc\n\td\n") == .tabs, "detect: tab-indented")
    expect(IndentStyle.detect(in: "{\n  \"a\": {\n    \"b\": 1\n  }\n}\n") == .spaces(2), "detect: 2-space JSON")
    expect(IndentStyle.detect(in: "def f():\n    if x:\n        y()\n    return\n") == .spaces(4), "detect: 4-space")
    expect(IndentStyle.detect(in: "a\n    b\n    c\n\td\n    e\n") == .spaces(4), "detect: mixed, spaces majority")
    expect(IndentStyle.detect(in: "a\n\tb\n\tc\n  d\n") == .tabs, "detect: mixed, tabs majority")
    expect(IndentStyle.detect(in: "services:\n  web:\n    image: x\n    ports:\n      - 80\n  db:\n    image: y\n") == .spaces(2),
           "detect: nested YAML maps")
    expect(IndentStyle.detect(in: "- one\n  - two\n    - three\n- four\n") == .spaces(2), "detect: Markdown list")
    expect(IndentStyle.detect(in: "a\n    \n\t\n\t\n  b\n  c\n") == .spaces(2), "detect: blank lines ignored")
    expect(IndentStyle.detect(in: "a\nb\n\nc") == nil, "detect: no indented lines is nil")
    expect(IndentStyle.detect(in: "") == nil, "detect: empty is nil")
    expect(IndentStyle.detect(in: "x\n" + String(repeating: "a\n", count: 1_000) + "  b\n") == nil,
           "detect: samples only the first 1,000 non-blank lines")
}

do {
    let yaml = { (d: IndentStyle?) in IndentStyle.effective(detected: d, fileExtension: "yml") }
    expect(yaml(nil) == .spaces(2), "effective: YAML without evidence uses 2 spaces")
    expect(yaml(.tabs) == .spaces(2), "effective: tab-indented YAML still uses spaces")
    expect(yaml(.spaces(4)) == .spaces(4), "effective: YAML keeps its detected unit")
    expect(IndentStyle.effective(detected: .spaces(4), fileExtension: "YAML") == .spaces(4), "effective: YAML extension is case-insensitive")
    expect(IndentStyle.effective(detected: nil, fileExtension: "md") == .tabs, "effective: no evidence keeps the tab")
    expect(IndentStyle.effective(detected: nil, fileExtension: nil) == .tabs, "effective: untitled keeps the tab")
    expect(IndentStyle.effective(detected: .spaces(2), fileExtension: "json") == .spaces(2), "effective: other files follow detection")
}

func applied(_ text: String, _ edit: IndentStyle.Edit?) -> String {
    guard let edit else { return text }
    return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

do {
    let two = IndentStyle.spaces(2), four = IndentStyle.spaces(4)
    let caret = { (at: Int) in NSRange(location: at, length: 0) }

    // Single line: tab stop math.
    var e = four.indent(in: "ab", selection: caret(0))
    expect(applied("ab", e) == "    ab" && e.selection == caret(4), "indent: caret at line start inserts a full unit")
    e = four.indent(in: "x\nab", selection: caret(3))
    expect(applied("x\nab", e) == "x\na   b" && e.selection == caret(6), "indent: spaces up to the next stop")
    e = two.indent(in: "abc", selection: caret(3))
    expect(applied("abc", e) == "abc " && e.selection == caret(4), "indent: odd column reaches the next 2-stop")
    e = four.indent(in: "\tab", selection: caret(2))
    expect(applied("\tab", e) == "\ta   b", "indent: a tab before the caret counts as a stop")
    e = IndentStyle.tabs.indent(in: "ab", selection: caret(1))
    expect(applied("ab", e) == "a\tb" && e.selection == caret(2), "indent: tabs insert a tab character")
    e = two.indent(in: "abcd", selection: NSRange(location: 1, length: 2))
    expect(applied("abcd", e) == "a d" && e.selection == caret(2), "indent: a selection within one line is replaced")

    // Multiple lines: every touched line, empty lines skipped, selection grows.
    let text = "a\n\nbc\nd"
    e = two.indent(in: text as NSString, selection: NSRange(location: 0, length: 4))
    expect(applied(text, e) == "  a\n\n  bc\nd", "indent: block indents touched lines, skips empty ones")
    expect(e.selection == NSRange(location: 0, length: 8), "indent: block selection covers the same text")
    e = IndentStyle.tabs.indent(in: text as NSString, selection: NSRange(location: 1, length: 5))
    expect(applied(text, e) == "\ta\n\n\tbc\nd", "indent: selection ending at a line start leaves that line")
    expect(e.selection == NSRange(location: 2, length: 6), "indent: block selection starting mid-line shifts with it")

    // Outdent.
    var o = four.outdent(in: "    ab", selection: caret(6))
    expect(applied("    ab", o) == "ab" && o?.selection == caret(2), "outdent: removes one unit")
    o = four.outdent(in: "  ab", selection: caret(1))
    expect(applied("  ab", o) == "ab" && o?.selection == caret(0), "outdent: fewer than a unit of spaces")
    o = two.outdent(in: "\t\tab", selection: caret(4))
    expect(applied("\t\tab", o) == "\tab" && o?.selection == caret(3), "outdent: removes one tab")
    o = IndentStyle.tabs.outdent(in: "      ab", selection: caret(0))
    expect(applied("      ab", o) == "  ab" && o?.selection == caret(0), "outdent: tabs style removes up to 4 spaces")
    expect(two.outdent(in: "ab\n  c", selection: caret(1)) == nil, "outdent: line without indentation is left alone")
    let block = "    a\nb\n  c\n"
    o = four.outdent(in: block as NSString, selection: NSRange(location: 4, length: 9))
    expect(applied(block, o) == "a\nb\nc\n", "outdent: block outdents every touched line")
    expect(o?.selection == NSRange(location: 0, length: 7), "outdent: block selection covers the same text")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
