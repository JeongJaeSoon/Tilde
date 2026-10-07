//
//  FormatCommands.swift
//  Tilde
//

import SwiftUI
import AppKit

/// Format menu: Markdown bold / italic / link (⌘B / ⌘I / ⌘K). Menu key
/// equivalents, so the shortcuts work under any input source. Each item
/// sends its action down the responder chain to the focused editor.
struct FormatCommands: Commands {
    /// True for the frontmost editable Markdown document in the editor;
    /// nil or false disables the menu.
    @FocusedValue(\.markdownFormatting) private var markdownFormatting

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { send(#selector(EditorTextView.toggleMarkdownBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!isEnabled)
            Button("Italic") { send(#selector(EditorTextView.toggleMarkdownItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!isEnabled)

            Divider()

            Button("Add Link…") { send(#selector(EditorTextView.addMarkdownLink(_:))) }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!isEnabled)
        }
    }

    private var isEnabled: Bool { markdownFormatting == true }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

struct MarkdownFormattingFocusedValueKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var markdownFormatting: Bool? {
        get { self[MarkdownFormattingFocusedValueKey.self] }
        set { self[MarkdownFormattingFocusedValueKey.self] = newValue }
    }
}
