//
//  EditorTextView+Indent.swift
//  Tilde
//

import AppKit

/// Tab and ⇧Tab follow the document's indentation (#18). The text itself
/// is computed by `IndentStyle`; this applies it as one ordinary edit, so
/// undo, the dirty state, the stylers' incremental restyle, and the
/// line-number gutter all see it like typing.
extension EditorTextView {
    override func insertTab(_ sender: Any?) {
        // While an input method is composing, Tab belongs to it (the
        // Japanese IME moves through candidates with it).
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, let storage = textStorage else {
            super.insertTab(sender)
            return
        }
        apply(indentStyle.indent(in: storage.mutableString, selection: selectedRange()))
    }

    override func insertBacktab(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, let storage = textStorage else {
            super.insertBacktab(sender)
            return
        }
        guard let edit = indentStyle.outdent(in: storage.mutableString, selection: selectedRange()) else { return }
        apply(edit)
    }

    private func apply(_ edit: IndentStyle.Edit) {
        // Each Tab or ⇧Tab is its own undo step, not merged into typing.
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        breakUndoCoalescing()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }
}
