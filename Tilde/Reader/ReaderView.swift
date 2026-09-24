//
//  ReaderView.swift
//  Tilde
//

import SwiftUI
import AppKit

/// Read-only rendered Markdown for Reader mode (⌘⇧R).
///
/// Shares the editor's content width, padding, and semantic colors so
/// entering Reader reads as the syntax markers dissolving. Selection,
/// copy, and ⌘F Find come from the underlying `NSTextView` for free.
struct ReaderView: NSViewRepresentable {
    var document: TextDocument
    var fontSize: CGFloat
    /// The document's file URL: its directory anchors relative image and
    /// link paths. Passed in (rather than read off the window) so the
    /// first render can already resolve them.
    var fileURL: URL?
    /// Asks the editor for its reading position (fraction of characters
    /// above the viewport top) so Reader opens at the same place instead of
    /// the top. Read at makeNSView time — the editor is still mounted
    /// underneath — so ANY entry path gets position restore for free.
    var entryFraction: () -> CGFloat = { 0 }
    /// Called when the user presses Esc to leave Reader.
    var onExit: () -> Void

    private var baseURL: URL? { fileURL?.deletingLastPathComponent() }

    func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit 1 stack explicitly: NSTextTable (used for
        // Markdown tables) is not supported by TextKit 2. The preview is
        // read-only and re-rendered per toggle, so TextKit 1 here is fine;
        // the editor stays on TextKit 2.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Read-only view: non-contiguous layout lets the entry-position
        // scroll estimate the height above its target instead of laying out
        // the whole prefix on the main thread.
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        // Width tracks the view; height is unbounded so the text view grows to
        // fit all content and the scroll view can reach the bottom.
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        let textView = ExitingTextView(frame: .zero, textContainer: container)
        textView.onExit = onExit
        // The coordinator handles clicks on local and in-document links.
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: EditorTheme.padding, height: EditorTheme.padding)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Links open in the user's browser; nothing is editable.
        textView.isAutomaticLinkDetectionEnabled = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        context.coordinator.textView = textView
        // Render exactly once: relative paths resolve against the passed-in
        // fileURL, so nothing needs to wait for the window (a second render
        // here used to double the entry cost on large documents). The entry
        // scroll is deferred inside render — at this point the view has no
        // window and a zero frame, so a scroll now would be computed against
        // bogus geometry and thrown away one runloop later anyway.
        context.coordinator.render(
            document: document,
            fontSize: fontSize,
            baseURL: baseURL,
            restoringFraction: entryFraction()
        )

        // Re-center the capped content column when the window resizes;
        // updateNSView alone doesn't fire on live resize.
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        // Become first responder so Esc (cancelOperation) reaches this view.
        // The find bar, when open, takes the responder chain first, so ⌘F's
        // own Esc still closes the search before this exits Reader.
        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? ExitingTextView)?.onExit = onExit
        context.coordinator.renderIfNeeded(document: document, fontSize: fontSize, baseURL: baseURL)
        context.coordinator.centerContent(in: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        private var renderedText: String?
        private var renderedSize: CGFloat?
        private var renderedBaseURL: URL?
        /// Bumped per render so a slow background render can tell if it has
        /// been superseded before it installs its result.
        private var generation = 0

        /// Documents at or below this size render synchronously (no flash);
        /// larger ones render off the main thread so ⌘⇧P never freezes.
        private static let syncThreshold = 256 * 1024

        func renderIfNeeded(document: TextDocument, fontSize: CGFloat, baseURL: URL?) {
            if document.textStorage.string == renderedText, fontSize == renderedSize, baseURL == renderedBaseURL { return }
            render(document: document, fontSize: fontSize, baseURL: baseURL)
        }

        func render(document: TextDocument, fontSize: CGFloat, baseURL: URL?, restoringFraction: CGFloat? = nil) {
            guard let textView else { return }
            let text = document.textStorage.string
            renderedText = text
            renderedSize = fontSize
            renderedBaseURL = baseURL
            generation += 1
            let token = generation
            let renderer = MarkdownRenderer(fontSize: fontSize, baseURL: baseURL)

            if text.utf8.count <= Self.syncThreshold {
                let rendering = renderer.renderDocument(text)
                textView.textStorage?.setAttributedString(rendering.text)
                if let restoringFraction = restoringFraction.map({
                    MarkdownRenderer.renderedFraction($0, hiddenLength: rendering.hiddenLength, sourceLength: (text as NSString).length)
                }) {
                    // Geometry (window, frame) is only trustworthy one
                    // runloop after makeNSView; the content is already in
                    // place, so the deferred scroll doesn't flash.
                    DispatchQueue.main.async { [weak self] in
                        self?.scroll(toCharacterFraction: restoringFraction)
                    }
                }
                return
            }

            // Apple's Markdown parser dominates the cost on multi-hundred-KB
            // documents and cannot be sped up, so render off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                let rendering = renderer.renderDocument(text)
                let rendered = rendering.text
                let restoringFraction = restoringFraction.map {
                    MarkdownRenderer.renderedFraction($0, hiddenLength: rendering.hiddenLength, sourceLength: (text as NSString).length)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, let textView = self.textView else { return }
                    textView.textStorage?.setAttributedString(rendered)
                    if let restoringFraction { self.scroll(toCharacterFraction: restoringFraction) }
                }
            }
        }

        /// Scrolls so the character at `fraction` of the rendered text sits at
        /// the top of the viewport — an approximate but cheap mapping of the
        /// editor's position (source and rendered lengths differ only by the
        /// dissolved markers).
        private func scroll(toCharacterFraction fraction: CGFloat) {
            guard fraction > 0, let textView else { return }
            let length = (textView.string as NSString).length
            guard length > 0 else { return }
            scroll(toCharacterIndex: min(length - 1, Int(CGFloat(length) * fraction)))
        }

        /// Scrolls the line containing `target` to the top of the viewport.
        private func scroll(toCharacterIndex target: Int) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            // Lay out only the target's own range: with non-contiguous
            // layout TextKit estimates the height above it, so a large
            // document doesn't pay a full main-thread layout pass here.
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: target, length: 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: target)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            textView.scroll(NSPoint(x: 0, y: lineRect.minY + textView.textContainerInset.height))
        }

        // MARK: - Link clicks

        /// Routes clicked links: `#fragment` jumps to the matching rendered
        /// heading, local files open as their own document windows, and
        /// anything with a scheme falls through to the system default
        /// (browser, Mail, …). The renderer has already resolved relative
        /// paths against the document's directory.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }

            if url.scheme == nil, url.relativePath.isEmpty, let fragment = url.fragment {
                scroll(toAnchor: fragment)
                return true
            }

            if url.isFileURL {
                // Strip a `file.md#section` fragment; open the file itself.
                // Under the sandbox this succeeds only for paths the app can
                // already read — on failure the user just hears the beep.
                let fileOnly = URL(fileURLWithPath: url.path)
                NSDocumentController.shared.openDocument(withContentsOf: fileOnly, display: true) { _, _, error in
                    if error != nil { NSSound.beep() }
                }
                return true
            }

            return false
        }

        /// Jumps to the heading whose anchor slug matches `fragment`
        /// (percent-decoded, then slugified the same way heading text is).
        private func scroll(toAnchor fragment: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let decoded = fragment.removingPercentEncoding ?? fragment
            let target = MarkdownRenderer.anchorSlug(for: decoded)
            var location: Int?
            storage.enumerateAttribute(
                MarkdownRenderer.headingAnchorKey,
                in: NSRange(location: 0, length: storage.length)
            ) { value, range, stop in
                if let slug = value as? String, slug == target {
                    location = range.location
                    stop.pointee = true
                }
            }
            guard let location else {
                NSSound.beep()
                return
            }
            scroll(toCharacterIndex: location)
        }

        /// Markdown content is capped and centered like the editor.
        func centerContent(in scrollView: NSScrollView) {
            guard let textView else { return }
            let cap = EditorTheme.maxContentWidth(for: renderedSize ?? EditorTheme.defaultFontSize)
            let excess = scrollView.contentSize.width - cap
            let horizontal = max(EditorTheme.padding, excess / 2)
            let inset = NSSize(width: horizontal, height: EditorTheme.padding)
            if textView.textContainerInset != inset {
                textView.textContainerInset = inset
            }
        }

        @objc func viewFrameDidChange(_ notification: Notification) {
            guard let scrollView = textView?.enclosingScrollView else { return }
            centerContent(in: scrollView)
        }
    }

    /// NSTextView that leaves Reader on Esc, and paints one rounded band
    /// behind each code listing. The renderer tags listings with
    /// `codeBlockMarker` instead of giving their NSTextBlock a square
    /// background fill, so the code's "room" keeps the editor's exact
    /// geometry — same color, same 5pt corners — across ⌘⇧R.
    private final class ExitingTextView: NSTextView {
        var onExit: (() -> Void)?
        override func cancelOperation(_ sender: Any?) { onExit?() }

        override func drawBackground(in rect: NSRect) {
            super.drawBackground(in: rect)
            guard
                let layoutManager,
                let storage = textStorage,
                storage.length > 0
            else { return }

            EditorTheme.codeBackgroundColor.setFill()
            let origin = textContainerOrigin
            let pad = MarkdownRenderer.codeBlockPadding
            storage.enumerateAttribute(
                EditorTheme.codeBlockMarker,
                in: NSRange(location: 0, length: storage.length)
            ) { value, range, _ in
                guard value != nil else { return }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var union = CGRect.null
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, _, _ in
                    union = union.union(fragment)
                }
                guard !union.isNull else { return }
                if let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle {
                    union.size.height = max(0, union.height - style.lineSpacing)
                }
                let band = NSRect(
                    x: union.minX + origin.x - pad,
                    y: union.minY + origin.y - pad,
                    width: union.width + pad * 2,
                    height: union.height + pad * 2
                )
                guard band.intersects(rect) else { return }
                NSBezierPath(
                    roundedRect: band,
                    xRadius: EditorTheme.codeCornerRadius,
                    yRadius: EditorTheme.codeCornerRadius
                ).fill()
            }
        }
    }
}
