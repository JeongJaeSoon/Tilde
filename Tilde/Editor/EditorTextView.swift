//
//  EditorTextView.swift
//  Tilde
//

import AppKit

/// The editor's `NSTextView`, subclassed only to paint one continuous
/// background behind fenced code blocks.
///
/// Code lines are tagged with `EditorTheme.codeBlockMarker` by the styler;
/// a per-character `.backgroundColor` would render as ragged per-line
/// strips, so instead the layout fragments of each contiguous marked run
/// are unioned and filled as a single rounded rectangle.
final class EditorTextView: NSTextView {
    /// Shifts the text container left of the symmetric `textContainerInset`
    /// so the two horizontal margins can differ: with the line-number gutter
    /// shown, the text needs only a small gap on the left (the gutter is the
    /// reading margin) but the full padding on the right.
    var textOriginShiftX: CGFloat = 0 {
        didSet {
            guard oldValue != textOriginShiftX else { return }
            needsLayout = true
            needsDisplay = true
        }
    }

    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.x -= textOriginShiftX
        return origin
    }

    /// The buffer's invariant is LF-only line endings (the document
    /// normalizes at load and restores the original style at save — a
    /// literal `\r\n` surviving in the buffer would corrupt into `\r\r\n`
    /// on a CRLF save, and the line-number gutter counts `\n` alone).
    /// Paste and drag are the two ways foreign line endings get in; both
    /// funnel through this read, so normalize here.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string,
           let raw = pboard.string(forType: .string),
           raw.contains("\r") {
            insertText(LineEnding.normalizeToLF(raw).text, replacementRange: selectedRange())
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    /// A freshly created document window parks first-responder status on the
    /// window itself, so typing into a new (or newly opened) document went
    /// nowhere until the user clicked. Claim focus as soon as the editor
    /// lands in a window — deferred one runloop so window setup finishes
    /// first, and only when the window still holds focus, so a real
    /// responder (the find bar's field editor, a sheet) is never robbed.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if window.firstResponder === window {
                window.makeFirstResponder(self)
            }
        }
    }

    /// Text height the caret is drawn at, set by the coordinator from the
    /// current body font. `nil` leaves AppKit's rect untouched.
    var caretHeight: CGFloat?

    /// On the final (virtual) line after a blank line, TextKit 2 swallows the
    /// typing style's `lineSpacing` into the line box, and the caret comes
    /// out 1.5× the text height (#1). The caret is an `NSTextInsertionIndicator`
    /// subview; AppKit sizes its frame when the insertion point updates and
    /// again in `layout()`, so clamp after both. The view is flipped, so
    /// trimming the height keeps the top edge where AppKit put it.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        clampInsertionIndicator()
    }

    override func layout() {
        super.layout()
        clampInsertionIndicator()
    }

    private func clampInsertionIndicator() {
        guard let caretHeight else { return }
        for case let indicator as NSTextInsertionIndicator in subviews
        where indicator.frame.height > caretHeight {
            var frame = indicator.frame
            frame.size.height = caretHeight
            indicator.frame = frame
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard
            let layoutManager = textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let textStorage,
            textStorage.length > 0
        else { return }

        // The band spans from the (possibly shifted) text origin on the left
        // to the mirrored margin on the right; total side margins stay
        // 2 × inset.width regardless of the shift.
        let inset = textContainerInset
        let originX = textContainerOrigin.x
        let fillRect = { (union: CGRect) -> NSRect in
            NSRect(
                x: originX,
                y: union.minY + inset.height,
                width: max(0, self.bounds.width - inset.width * 2),
                height: union.height
            )
        }

        EditorTheme.codeBackgroundColor.setFill()

        var union = CGRect.null
        func flush() {
            guard !union.isNull else { return }
            NSBezierPath(
                roundedRect: fillRect(union),
                xRadius: EditorTheme.codeCornerRadius,
                yRadius: EditorTheme.codeCornerRadius
            ).fill()
            union = .null
        }

        // Only walk the visible viewport so scrolling stays cheap.
        let viewport = layoutManager.textViewportLayoutController.viewportRange
            ?? layoutManager.documentRange
        let maxY = rect.maxY

        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + inset.height > maxY { return false }

            let offset = contentManager.offset(
                from: contentManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            let isCode = offset < textStorage.length
                && textStorage.attribute(EditorTheme.codeBlockMarker, at: offset, effectiveRange: nil) != nil

            if isCode {
                union = union.union(frame)
            } else {
                flush()
            }
            return true
        }
        flush()
    }
}
