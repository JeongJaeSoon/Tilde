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

    /// Markdown editing (typed wrap, ⌘B / ⌘I / ⌘K) is on for
    /// Markdown documents; see EditorTextView+MarkdownEditing.swift.
    var formatsMarkdown = false

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

    /// What Tab inserts and ⇧Tab removes, set by the coordinator
    /// (see EditorTextView+Indent.swift).
    var indentStyle: IndentStyle = .tabs

    /// Text height of the body font and its `lineSpacing`, set by the
    /// coordinator. `nil` leaves the caret alone.
    var caretHeight: CGFloat?
    var bodyLineSpacing: CGFloat?

    /// The caret on the final (virtual) line — the one after a trailing
    /// newline — is laid out by TextKit 2 as an extra line inside the last
    /// paragraph's fragment, and its geometry is unreliable (#1, #7): the
    /// typing style's `lineSpacing` is swallowed into its box (1.5× caret),
    /// and the gap above it depends on how the line was reached and on
    /// whether the paragraph before is blank or first in the document
    /// (−8 pt, 0, or +8 pt off the rhythm). Text typed there lands on the
    /// rhythm, so the caret is placed where that text will appear: one
    /// `lineSpacing` below the bottom of the last real line, text-height
    /// tall. Measuring from the bottom keeps it right after a heading,
    /// whose line is taller than the body rhythm.
    ///
    /// Every other caret is left as TextKit lays it out: on a real line it
    /// already spans that line's text height, and a heading's caret must
    /// stay heading-tall — clamped to the body height it hugged the top of
    /// the glyphs, far above the baseline.
    ///
    /// The caret is an `NSTextInsertionIndicator` subview; AppKit sets its
    /// frame when the insertion point updates and again in `layout()`, so
    /// adjust after both. The view is flipped: origin is the top edge.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        adjustInsertionIndicator()
    }

    override func layout() {
        super.layout()
        adjustInsertionIndicator()
    }

    private func adjustInsertionIndicator() {
        guard let caretHeight, isCaretOnExtraLine else { return }
        let shift = extraLineCaretShift()
        for case let indicator as NSTextInsertionIndicator in subviews {
            var frame = indicator.frame
            frame.origin.y += shift
            frame.size.height = min(frame.height, caretHeight)
            if frame != indicator.frame { indicator.frame = frame }
        }
    }

    /// Whether the caret sits on the extra line: at the very end of an
    /// empty document or of one ending in a newline.
    private var isCaretOnExtraLine: Bool {
        guard let storage = textStorage else { return false }
        let selection = selectedRange()
        let length = storage.length
        return selection.length == 0 && selection.location == length
            && (length == 0 || storage.mutableString.character(at: length - 1) == 0x0A)
    }

    /// How far the extra line's caret must move to sit one `lineSpacing`
    /// below the last real line; 0 when there is no real line before it.
    private func extraLineCaretShift() -> CGFloat {
        guard let bodyLineSpacing, let layoutManager = textLayoutManager else { return 0 }

        // The last fragment holds the last real line followed by the extra line.
        var last: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.endLocation, options: [.ensuresLayout, .reverse]
        ) { fragment in last = fragment; return false }
        guard let last, last.textLineFragments.count >= 2 else { return 0 }
        let lines = last.textLineFragments
        let realBottom = lines[lines.count - 2].typographicBounds.maxY
        let extraTop = lines[lines.count - 1].typographicBounds.minY
        return realBottom + bodyLineSpacing - extraTop
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
