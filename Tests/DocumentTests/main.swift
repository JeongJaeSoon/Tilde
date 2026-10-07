// Tests for Tilde's document layer: FileEncoding, LineEnding, and the
// document-type decision. Compiled as a plain executable by Tests/run.sh —
// no XCTest, so the suite runs on machines with only the Command Line Tools.

import Foundation
import UniformTypeIdentifiers

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

// MARK: - Files macOS doesn't type as text (#29)

// Extension-less names and dotfiles are typed public.data, unknown
// extensions dyn.*; both must reach the document and open as plain text
// unless their decoded bytes look binary.
func refused(_ data: Data, as type: UTType = .data) -> Bool {
    TextDocument.isRefusedAsBinary(contentType: type, decoded: FileEncoding.decode(data).string)
}

do {
    let types = TextDocument.readableContentTypes
    expect(types.first == .plainText, "new documents still default to plain text")
    expect(types.last == .data, "public.data is the last readable type")
    expect(TextDocument.writableContentTypes == Array(types.dropLast()),
           "public.data is readable but not offered in the save panel")
    let unknown = UTType(filenameExtension: "tildeunknownext")!
    expect(unknown.isDynamic && unknown.conforms(to: .data), "unknown extension is a dynamic data type")
    expect(types.contains { unknown.conforms(to: $0) }, "unknown extension is readable")
    expect(!unknown.conforms(to: .markdown) && !UTType.data.conforms(to: .markdown),
           "data types never open as markdown")
    expect(TextDocument.isMarkdown(openedAsMarkdown: UTType.data.conforms(to: .markdown),
                                   fileURL: URL(fileURLWithPath: "/tmp/id_ed25519")) == false,
           "extension-less data file opens as plain text")
}

do {
    let pem = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        -----END OPENSSH PRIVATE KEY-----

        """
    expect(!refused(Data(pem.utf8)), "PEM private key opens")
    let pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl user@host\n"
    expect(!refused(Data(pub.utf8)), "OpenSSH public key opens")
    expect(!refused(Data(".DS_Store\nbuild/\n*.xcuserstate\n".utf8)), ".gitignore body opens")
    expect(!refused(Data("API_KEY=secret\n".utf8)), ".env body opens")
    let utf16 = "KEY=value\nOTHER=1\n"
    expect(!refused(utf16.data(using: .utf16LittleEndian)!), "BOM-less UTF-16 LE opens")
    expect(!refused(utf16.data(using: .utf16BigEndian)!), "BOM-less UTF-16 BE opens")
    expect(!refused(Data()), "empty file opens")

    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
                    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06])
    expect(refused(png), "PNG header is refused")
    expect(refused(png, as: .png), "PNG typed as image is refused")
    var pdf = Data("%PDF-1.7\n%\u{E2}\u{E3}\u{CF}\u{D3}\n1 0 obj\n<< /Length 8 /Filter /FlateDecode >>\nstream\n".utf8)
    pdf.append(contentsOf: [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])
    expect(refused(pdf, as: .pdf), "PDF with a binary stream is refused")
    expect(refused(Data(count: 4096)), "all-zero file is refused")

    var lateNUL = Data(repeating: 0x61, count: 9000)
    lateNUL.append(0)
    expect(!refused(lateNUL), "NUL past the first 8,000 characters doesn't refuse")

    // Text-typed files skip the guard: a .txt with a NUL still opens.
    expect(!refused(Data("a\u{0}b".utf8), as: .plainText), "text-typed file is never refused")
    expect(!refused(Data("a\u{0}b".utf8), as: .json), "text-family file is never refused")
    expect(refused(Data("a\u{0}b".utf8)), "data-typed file with an early NUL is refused")

    // AppKit builds the alert title from the failure reason, not the description.
    let error = TextDocument.notTextFileError as NSError
    expect(error.localizedFailureReason == "This file isn't a text file.",
           "binary refusal names the reason in the alert title")
    expect(error.localizedRecoverySuggestion?.hasPrefix("Tilde opens text files only.") == true,
           "binary refusal explains what Tilde opens")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
