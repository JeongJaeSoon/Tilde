//
//  EditorTextView+MarkdownEditing.swift
//  Tilde
//

import AppKit

/// Markdown editing in the editor: a typed marker wraps the selection,
/// and ⌘B / ⌘I / ⌘K (the Format menu).
/// The transforms live in `MarkdownEditing`; this applies them as ordinary
/// edits. Active only while `formatsMarkdown` is on and the text is editable.
extension EditorTextView {
    private var formatsEditableMarkdown: Bool {
        formatsMarkdown && isEditable && selectedRanges.count == 1
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Text committed by an input method (marked text) is typed as is,
        // and the full-width `＊` isn't a wrap character.
        if formatsEditableMarkdown, !hasMarkedText(),
           replacementRange.location == NSNotFound || replacementRange == selectedRange(),
           let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
           MarkdownEditing.wrapPairs[typed] != nil,
           let storage = textStorage,
           let edit = MarkdownEditing.surround(storage.mutableString, selection: selectedRange(), with: typed) {
            applyMarkdownEdit(edit, actionName: nil)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    @objc func toggleMarkdownBold(_ sender: Any?) {
        toggleMarkdownEmphasis(.bold, actionName: String(localized: "Bold"))
    }

    @objc func toggleMarkdownItalic(_ sender: Any?) {
        toggleMarkdownEmphasis(.italic, actionName: String(localized: "Italic"))
    }

    @objc func addMarkdownLink(_ sender: Any?) {
        guard formatsEditableMarkdown, let storage = textStorage else { return }
        let url = NSPasteboard.general.string(forType: .string).flatMap(MarkdownEditing.linkableURL(from:))
        guard let edit = MarkdownEditing.link(in: storage.mutableString, selection: selectedRange(), url: url) else {
            NSSound.beep()
            return
        }
        applyMarkdownEdit(edit, actionName: String(localized: "Add Link"))
    }

    private func toggleMarkdownEmphasis(_ emphasis: MarkdownEditing.Emphasis, actionName: String) {
        guard formatsEditableMarkdown, let storage = textStorage else { return }
        guard let edit = MarkdownEditing.toggleEmphasis(emphasis, in: storage.mutableString, selection: selectedRange()) else {
            NSSound.beep()
            return
        }
        applyMarkdownEdit(edit, actionName: actionName)
    }

    /// Applies an edit the way typing does — `shouldChangeText` registers
    /// undo and `didChangeText` notifies the delegate — so undo, the dirty
    /// state, the styler's incremental restyle, and the gutter all see an
    /// ordinary edit. The coalescing breaks keep it one undo step, separate
    /// from typing on either side.
    func applyMarkdownEdit(_ edit: MarkdownEditing.Edit, actionName: String?) {
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        if let actionName { undoManager?.setActionName(actionName) }
        breakUndoCoalescing()
    }
}
