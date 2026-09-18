//
//  TextEditorView.swift
//  Tilde
//

import SwiftUI
import AppKit

/// Lets `EditorView` talk to the AppKit text view without holding a
/// reference to it: ask for the current reading position (fraction of
/// characters above the viewport top) and hand keyboard focus back after
/// Reader mode exits.
final class EditorScrollBridge {
    var readFraction: () -> CGFloat = { 0 }
    var focusEditor: () -> Void = {}
}

/// Wraps an AppKit `NSTextView` (TextKit 2) for SwiftUI.
///
/// Undo, Find, spell checking, IME, and drag & drop all come from the
/// system text view — Tilde switches them on rather than building them.
/// The view renders the document's own `NSTextStorage`, so typing never
/// round-trips the buffer through SwiftUI.
struct TextEditorView: NSViewRepresentable {
    var document: TextDocument

    /// Markdown-ness is derived from the live file URL by `EditorView`, so
    /// it can change at Save As time.
    var isMarkdown: Bool
    var fontSize: CGFloat
    var wordWrap: Bool
    var showLineNumbers: Bool
    var markdownStyling: Bool
    /// The document's file URL, used to pick a code highlighter by extension.
    var fileURL: URL?
    /// Reader-entry position bridge; optional so previews/tests can omit it.
    var scrollBridge: EditorScrollBridge? = nil

    /// The settings state last pushed into AppKit, for cheap diffing.
    struct AppliedSettings: Equatable {
        var isMarkdown: Bool
        var fontSize: CGFloat
        var wordWrap: Bool
        var showLineNumbers: Bool
        var stylerActive: Bool
        var codeLanguage: CodeSyntaxStyler.Language?
    }

    /// JSON/YAML highlighting is chosen by extension, and never for a
    /// Markdown document.
    private var codeLanguage: CodeSyntaxStyler.Language? {
        guard !isMarkdown else { return nil }
        switch fileURL?.pathExtension.lowercased() {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        default: return nil
        }
    }

    private var desiredSettings: AppliedSettings {
        AppliedSettings(
            isMarkdown: isMarkdown,
            fontSize: fontSize,
            wordWrap: wordWrap,
            showLineNumbers: showLineNumbers,
            stylerActive: isMarkdown && markdownStyling,
            codeLanguage: codeLanguage
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit 2 stack explicitly so the text view can be our
        // EditorTextView subclass (which paints code-block backgrounds).
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator

        // Editing behavior
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Plain-text editor: smart quotes/dashes would corrupt code and config files.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Appearance
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: EditorTheme.padding, height: EditorTheme.padding)

        // Layout: grow vertically; wrap is configured from settings below.
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Markdown caps its content width; recompute the insets as the
        // window resizes.
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        // No scroller when the document fits — a resting scrollbar is visual
        // noise in a short file.
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        context.coordinator.attach(document, to: textView, in: scrollView, settings: desiredSettings)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.undoManager = context.environment.undoManager

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // A new document instance (e.g. Revert To) swaps the backing storage.
        if context.coordinator.attachedDocument !== document {
            context.coordinator.attach(document, to: textView, in: scrollView, settings: desiredSettings)
            return
        }

        if context.coordinator.applied != desiredSettings {
            context.coordinator.apply(desiredSettings, to: textView, in: scrollView)
            context.coordinator.restyleAll()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        // The stylers die with the coordinator; don't leave the document's
        // storage pointing at a deallocated delegate.
        coordinator.attachedDocument?.textStorage.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorView
        /// The document's undo manager (from the SwiftUI environment), so text
        /// edits drive the window's dirty state, autosave, and ⌘Z.
        var undoManager: UndoManager?
        /// The Markdown styler (also drives plain-text body maintenance) and
        /// the code highlighter are kept so their incremental state survives
        /// setting changes; only one is the text storage's delegate at a time.
        private var markdownStyler: MarkdownStyler?
        private var codeStyler: CodeSyntaxStyler?
        private weak var activeHighlighter: (NSObject & SyntaxHighlighting)?
        var applied: AppliedSettings?
        private(set) weak var attachedDocument: TextDocument?
        private(set) weak var textView: NSTextView?

        init(parent: TextEditorView) {
            self.parent = parent
        }

        // MARK: - Document attachment

        /// Points the text view at the document's own storage, then styles
        /// the whole buffer exactly once.
        func attach(_ document: TextDocument, to textView: NSTextView, in scrollView: NSScrollView, settings: AppliedSettings) {
            attachedDocument = document
            self.textView = textView
            textView.textContentStorage?.textStorage = document.textStorage
            // Lossily decoded documents are read-only: every byte the user
            // could save is already not the original (TextDocument blocks
            // the write as well).
            textView.isEditable = !document.isLossy
            parent.scrollBridge?.readFraction = { [weak self] in
                self?.currentReadingFraction() ?? 0
            }
            parent.scrollBridge?.focusEditor = { [weak self] in
                self?.claimKeyboardFocus()
            }
            apply(settings, to: textView, in: scrollView)
            restyleAll()
            // The storage swap invalidates the gutter's line index (Revert To
            // replaces the whole document instance).
            (scrollView.verticalRulerView as? LineNumberRulerView)?.rebuildLineIndex()
        }

        /// Makes the editor the window's first responder. Deferred one
        /// runloop so the Reader's text view (the outgoing responder) has
        /// unmounted by the time focus moves; used on Reader exit, where
        /// reclaiming focus is unconditionally correct. Initial focus for a
        /// fresh window is handled by `EditorTextView.viewDidMoveToWindow`.
        func claimKeyboardFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let textView = self?.textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }

        /// Fraction (0…1) of the document's characters above the top of the
        /// editor's viewport — used to open Reader at the same place.
        func currentReadingFraction() -> CGFloat {
            guard
                let textView,
                let length = attachedDocument?.textStorage.length, length > 0
            else { return 0 }

            let visible = textView.visibleRect
            let containerPoint = CGPoint(x: 0, y: visible.minY - textView.textContainerInset.height)
            guard containerPoint.y > 0 else { return 0 }

            if let layoutManager = textView.textLayoutManager,
               let contentManager = layoutManager.textContentManager,
               let fragment = layoutManager.textLayoutFragment(for: containerPoint) {
                var offset = contentManager.offset(
                    from: contentManager.documentRange.location,
                    to: fragment.rangeInElement.location
                )
                // Fragments span whole paragraphs, so interpolate by y
                // within the fragment: a document dominated by one long
                // soft-wrapped paragraph should map to its middle, not
                // snap to its start.
                let frame = fragment.layoutFragmentFrame
                if frame.height > 0 {
                    let fragmentLength = contentManager.offset(
                        from: fragment.rangeInElement.location,
                        to: fragment.rangeInElement.endLocation
                    )
                    let within = max(0, min(1, (containerPoint.y - frame.minY) / frame.height))
                    offset += Int(CGFloat(fragmentLength) * within)
                }
                return max(0, min(1, CGFloat(offset) / CGFloat(length)))
            }

            // Fallback: fraction of the scrollable range.
            let scrollable = textView.frame.height - visible.height
            guard scrollable > 0 else { return 0 }
            return max(0, min(1, visible.minY / scrollable))
        }

        // MARK: - Settings

        func apply(_ settings: AppliedSettings, to textView: NSTextView, in scrollView: NSScrollView) {
            let monospaced = !settings.isMarkdown

            // Pick the highlighter for this document: Markdown styling, code
            // highlighting by extension, or plain (Markdown styler in a
            // body-only mode, which also maintains empty-line spacing).
            let highlighter: NSObject & SyntaxHighlighting
            if settings.stylerActive {
                let s = markdownStyler ?? MarkdownStyler(); markdownStyler = s
                s.stylesMarkdown = true
                s.usesMonospacedBody = false
                highlighter = s
            } else if let language = settings.codeLanguage {
                let s = codeStyler ?? CodeSyntaxStyler(); codeStyler = s
                s.language = language
                highlighter = s
            } else {
                let s = markdownStyler ?? MarkdownStyler(); markdownStyler = s
                s.stylesMarkdown = false
                s.usesMonospacedBody = true
                highlighter = s
            }
            highlighter.fontSize = settings.fontSize
            activeHighlighter = highlighter
            attachedDocument?.textStorage.delegate = highlighter

            textView.typingAttributes = EditorTheme.typingAttributes(
                monospaced: monospaced,
                size: settings.fontSize
            )
            textView.defaultParagraphStyle = EditorTheme.paragraphStyle(
                for: EditorTheme.bodyFont(monospaced: monospaced, size: settings.fontSize)
            )
            if let editorView = textView as? EditorTextView {
                let font = EditorTheme.bodyFont(monospaced: monospaced, size: settings.fontSize)
                editorView.caretHeight = EditorTheme.caretHeight(monospaced: monospaced, size: settings.fontSize)
                editorView.lineRhythm = editorView.caretHeight! + EditorTheme.lineSpacing(for: font)
            }

            configureWordWrap(settings.wordWrap, textView: textView, scrollView: scrollView)
            configureLineNumbers(settings.showLineNumbers, textView: textView, scrollView: scrollView)
            applied = settings
            updateContentInsets(of: textView)
        }

        private func configureWordWrap(_ wrap: Bool, textView: NSTextView, scrollView: NSScrollView) {
            guard let container = textView.textContainer else { return }
            if wrap {
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
                container.widthTracksTextView = true
                textView.setFrameSize(NSSize(
                    width: scrollView.contentSize.width,
                    height: textView.frame.height
                ))
                scrollView.hasHorizontalScroller = false
            } else {
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
                container.widthTracksTextView = false
                container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                scrollView.hasHorizontalScroller = true
            }
        }

        private func configureLineNumbers(_ show: Bool, textView: NSTextView, scrollView: NSScrollView) {
            if show {
                if scrollView.verticalRulerView == nil {
                    scrollView.verticalRulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
                }
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
            } else {
                scrollView.rulersVisible = false
            }
        }

        // MARK: - Typography

        /// Restyles the whole buffer through the active highlighter.
        func restyleAll() {
            guard let document = attachedDocument else { return }
            activeHighlighter?.restyleAll(document.textStorage)
        }

        private var isMarkdown: Bool { applied?.isMarkdown ?? false }

        /// Markdown documents keep their content no wider than
        /// `EditorTheme.maxContentWidth`, centered; plain text uses the full width.
        func updateContentInsets(of textView: NSTextView) {
            // With the gutter shown it supplies the LEFT reading margin, so
            // the text only needs a small gap beside the numbers — but the
            // RIGHT margin must keep the full padding. textContainerInset is
            // symmetric, so use the average of the two targets and shift the
            // container left by the difference (EditorTextView overrides
            // textContainerOrigin for this).
            var left = applied?.showLineNumbers == true ? EditorTheme.gutterTextInset : EditorTheme.padding
            var right = EditorTheme.padding
            if isMarkdown, applied?.wordWrap ?? true {
                let cap = EditorTheme.maxContentWidth(for: applied?.fontSize ?? EditorTheme.defaultFontSize)
                let half = (textView.frame.width - cap) / 2
                left = max(left, half)
                right = max(right, half)
            }
            let inset = NSSize(width: (left + right) / 2, height: EditorTheme.padding)
            if textView.textContainerInset != inset {
                textView.textContainerInset = inset
            }
            (textView as? EditorTextView)?.textOriginShiftX = inset.width - left
        }

        @objc func viewFrameDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateContentInsets(of: textView)
        }

        // MARK: - NSTextViewDelegate

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        /// Re-lays out the tail of the document after every edit.
        ///
        /// When an edit leaves the document ending in a newline, TextKit 2
        /// appends the final caret's extra line to the last paragraph's
        /// fragment incrementally — and on that path drops the spacing above
        /// it, so deleting a line's text back to empty parks the caret 8 pt
        /// higher than the same empty line reached with Return (#7). A fresh
        /// layout of that one paragraph computes it correctly; the range is
        /// a single paragraph, so this is cheap.
        func textDidChange(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                let layoutManager = textView.textLayoutManager,
                let contentManager = layoutManager.textContentManager,
                let storage = textView.textStorage
            else { return }
            let length = storage.length
            guard length > 0, storage.mutableString.character(at: length - 1) == 0x0A else { return }
            let tail = storage.mutableString.paragraphRange(for: NSRange(location: length - 1, length: 0))
            guard
                let start = contentManager.location(contentManager.documentRange.location, offsetBy: tail.location),
                let range = NSTextRange(location: start, end: contentManager.documentRange.endLocation)
            else { return }
            layoutManager.invalidateLayout(for: range)
        }
    }
}
