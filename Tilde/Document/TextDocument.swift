//
//  TextDocument.swift
//  Tilde
//

import SwiftUI
import AppKit
// ObservableObject's synthesized objectWillChange lives in Combine; with
// MemberImportVisibility enabled the conformance needs the direct import.
import Combine
import UniformTypeIdentifiers

// Plain values, usable from the document's nonisolated save path.
nonisolated extension UTType {
    /// Markdown is not a system-declared type; Tilde imports it (see Info.plist).
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    /// TOML has no system UTI either; Tilde imports it so `.toml` files are
    /// recognized as plain text and open (see Info.plist).
    static let toml = UTType(importedAs: "io.toml.toml")
}

/// A plain-text document.
///
/// The document owns the `NSTextStorage` and the text view renders it
/// directly — keystrokes never copy the buffer through SwiftUI. The
/// content is materialized as a `String` only when a save snapshot is
/// taken (DESIGN.md §1).
///
/// Isolation: `ReferenceFileDocument` is a `Sendable`, nonisolated protocol
/// because SwiftUI snapshots the document and then serializes that snapshot
/// (`fileWrapper`) on a background queue while the user keeps editing. So
/// the class is `nonisolated` — the project's MainActor default would only
/// be an illusion here, since the protocol witnesses run wherever SwiftUI
/// calls them — and its metadata is immutable `let`s, safe to read from
/// any thread. The one exception is `textStorage`, below.
nonisolated final class TextDocument: ReferenceFileDocument {
    /// The live buffer the editor's `NSTextView` displays.
    ///
    /// `nonisolated(unsafe)` is deliberate and narrow: `NSTextStorage` is an
    /// AppKit object that carries no `Sendable` annotation, and the compiler
    /// cannot see that every access is on the main thread — the text view's
    /// edits, the views that read it, and `snapshot`, which SwiftUI takes
    /// before handing the document to the background writer. Isolating the
    /// property to the main actor instead would forbid initializing it here,
    /// because `ReferenceFileDocument`'s initializers are nonisolated and
    /// SwiftUI documents no thread for them. `fileWrapper`, the only witness
    /// that does run off-main, never touches this property.
    nonisolated(unsafe) let textStorage: NSTextStorage

    /// Captured at load, preserved on save.
    let encoding: FileEncoding
    let lineEnding: LineEnding

    /// Each original line's ending, for a file that mixes styles; `nil`
    /// for uniform files, which restore `lineEnding` everywhere.
    let mixedLineEndings: MixedLineEndings?

    /// True when the file's bytes could not be decoded exactly (invalid
    /// UTF-8, BOM-less UTF-16 CJK, legacy encodings): the in-memory text
    /// contains substitution characters, so writing it back would corrupt
    /// the original. Such documents open read-only and refuse to save.
    let isLossy: Bool

    /// Whether this document was OPENED as Markdown. The editor combines
    /// this with the live file URL (see `isMarkdown(openedAsMarkdown:fileURL:)`)
    /// so a document saved with a different extension switches modes
    /// without reopening.
    let isMarkdown: Bool

    /// File extensions treated as Markdown (mirrors Info.plist's imported
    /// `net.daringfireball.markdown` declaration).
    static func isMarkdownExtension(_ ext: String) -> Bool {
        ["md", "markdown", "mdown"].contains(ext.lowercased())
    }

    /// Markdown-ness for a document as it exists NOW: the live extension
    /// wins, so Save As from `.md` to `.txt` (or back) switches typography,
    /// styling, code highlighting, and the Reader command immediately. The
    /// open-time type is only the fallback for extension-less files and
    /// untitled documents.
    static func isMarkdown(openedAsMarkdown: Bool, fileURL: URL?) -> Bool {
        if let ext = fileURL?.pathExtension, !ext.isEmpty {
            return isMarkdownExtension(ext)
        }
        return openedAsMarkdown
    }

    /// `.plainText` first: new documents default to `.txt` in the save panel.
    /// `.text` admits the broader family (JSON, YAML, XML, …) via Open With —
    /// all treated as plain text (PRODUCT.md §6). `.data` last admits files
    /// macOS can't type as text from their name (`id_ed25519`, `.gitignore`,
    /// `id_ed25519.pub`); `init(configuration:)` refuses the binary ones.
    static var readableContentTypes: [UTType] { [.plainText, .markdown, .toml, .text, .data] }

    /// Readable minus `.data`, which would otherwise show up as an extra
    /// entry in the save panel's File Format menu. A file opened as
    /// `public.data` still saves in place under its own name (checked in
    /// the running app; see VERIFY.md "File associations").
    static var writableContentTypes: [UTType] { [.plainText, .markdown, .toml, .text] }

    /// Decodes a file, refusing it when it looks binary. Only files macOS
    /// did NOT type as text are checked, so a text-typed file still always
    /// opens (FileEncoding's "never refuse a text file"). A prefix is
    /// checked before the whole file so a large binary is refused without
    /// decoding all of it.
    static func decodeRefusingBinary(
        _ data: Data, contentType: UTType
    ) throws -> (string: String, encoding: FileEncoding, isLossy: Bool) {
        let checked = !contentType.conforms(to: .text)
        if checked, FileEncoding.looksBinary(FileEncoding.decode(FileEncoding.binaryCheckPrefix(of: data)).string) {
            throw notTextFileError
        }
        let decoded = FileEncoding.decode(data)
        // The whole file has the last word: a UTF-16 decode can still fail
        // past the prefix and fall back to UTF-8, NULs included.
        if checked, FileEncoding.looksBinary(decoded.string) {
            throw notTextFileError
        }
        return decoded
    }

    /// The open-error alert's title is AppKit's "The document “X” could not
    /// be opened." followed by the failure reason; the description is not
    /// shown, so the reason carries the message.
    static var notTextFileError: CocoaError {
        let reason = String(localized: "This file isn't a text file.")
        return CocoaError(.fileReadCorruptFile, userInfo: [
            NSLocalizedDescriptionKey: reason,
            NSLocalizedFailureReasonErrorKey: reason,
            NSLocalizedRecoverySuggestionErrorKey: String(
                localized: "Tilde opens text files only. Images, PDFs, and other binary files can't be edited."
            ),
        ])
    }

    init() {
        textStorage = NSTextStorage()
        encoding = .default
        lineEnding = .lf
        mixedLineEndings = nil
        isLossy = false
        isMarkdown = false
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try Self.decodeRefusingBinary(data, contentType: configuration.contentType)
        let normalized = LineEnding.normalizeToLF(decoded.string, recordingMixed: true)
        textStorage = NSTextStorage(string: normalized.text)
        encoding = decoded.encoding
        lineEnding = normalized.lineEnding
        mixedLineEndings = normalized.mixed
        isLossy = decoded.isLossy
        isMarkdown = configuration.contentType.conforms(to: .markdown)
    }

    /// Taken while editing is paused, before the background write; this is
    /// the only place the buffer is read on the document's behalf.
    func snapshot(contentType: UTType) throws -> String {
        textStorage.string
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        // A lossily decoded buffer contains substitution characters where
        // the original had bytes Tilde couldn't decode; writing it out
        // would destroy those bytes irrecoverably. The editor is read-only
        // for these documents — this guard is the backstop for any other
        // save path (autosave, Versions, scripted saves).
        guard !isLossy else {
            throw CocoaError(.fileWriteInapplicableStringEncoding, userInfo: [
                NSLocalizedDescriptionKey: String(
                    localized: "This file uses an encoding Tilde can't fully read, so saving would corrupt it."
                ),
                NSLocalizedRecoverySuggestionErrorKey: String(
                    localized: "The document is shown read-only to protect the original file. Copy text out of it, or convert the file to UTF-8 with another tool."
                ),
            ])
        }
        // The buffer should already be LF-only (normalized at load, and the
        // editor normalizes paste/drop), but restore() rewrites every `\n`
        // — a stray literal `\r\n` would corrupt into `\r\r\n` on a CRLF
        // document. Re-normalize as a cheap belt-and-braces pass.
        let normalized = LineEnding.normalizeToLF(snapshot).text
        let restored = mixedLineEndings?.restore(in: normalized, dominant: lineEnding)
            ?? lineEnding.restore(in: normalized)
        let data = encoding.encode(restored)
        return FileWrapper(regularFileWithContents: data)
    }
}
