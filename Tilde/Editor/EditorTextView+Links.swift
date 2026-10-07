//
//  EditorTextView+Links.swift
//  Tilde
//

import AppKit

/// ⌘-click follows a styled Markdown link with Reader's rules, and ⌘ held
/// over one shows the pointing hand. Without ⌘, clicks and the cursor are
/// NSTextView's own.
extension EditorTextView {
    private static let trackingTag = "tildeLinkCursor"
    private static let commandKeyCodes: Set<UInt16> = [54, 55]

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, Self.isCommandOnly(event.modifierFlags),
           let target = linkTarget(under: event.locationInWindow) {
            follow(target)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateLinkCursor(flags: event.modifierFlags, at: event.locationInWindow)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        updateLinkCursor(flags: event.modifierFlags, at: event.locationInWindow)
    }

    /// Only ⌘ itself pressed or released changes the cursor; other
    /// modifiers (Shift while typing) leave it to the text view.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard Self.commandKeyCodes.contains(event.keyCode),
              let point = window?.mouseLocationOutsideOfEventStream else { return }
        if Self.isCommandOnly(event.modifierFlags) {
            updateLinkCursor(flags: event.modifierFlags, at: point)
        } else if visibleRect.contains(convert(point, from: nil)) {
            NSCursor.iBeam.set()
        }
    }

    /// NSTextView's own tracking doesn't reliably deliver `mouseMoved`, so
    /// add one area that does; `inVisibleRect` keeps it current on scroll
    /// and resize.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard !trackingAreas.contains(where: { $0.userInfo?[Self.trackingTag] != nil }) else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: [Self.trackingTag: true]
        ))
    }

    private static func isCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .shift, .option, .control]) == .command
    }

    /// With ⌘ held: the pointing hand over a link, the I-beam elsewhere in
    /// the text (so the hand doesn't linger after leaving a link).
    private func updateLinkCursor(flags: NSEvent.ModifierFlags, at windowPoint: NSPoint) {
        guard Self.isCommandOnly(flags), visibleRect.contains(convert(windowPoint, from: nil)) else { return }
        (linkTarget(under: windowPoint) != nil ? NSCursor.pointingHand : NSCursor.iBeam).set()
    }

    /// The raw target of the styled link drawn under `windowPoint`. The
    /// insertion index sits after the character when the point is on that
    /// character's right half, so the character before it is tried too —
    /// each only when its glyph rect actually holds the point.
    private func linkTarget(under windowPoint: NSPoint) -> String? {
        guard let storage = textStorage, storage.length > 0, let window else { return nil }
        let index = characterIndexForInsertion(at: convert(windowPoint, from: nil))
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        for candidate in [index, index - 1] {
            guard let target = MarkdownStyler.linkTarget(at: candidate, in: storage) else { continue }
            let rect = firstRect(forCharacterRange: NSRange(location: candidate, length: 1), actualRange: nil)
            if rect.contains(screenPoint) { return target }
        }
        return nil
    }

    private func follow(_ target: String) {
        guard let url = MarkdownLink.url(fromTarget: target) else {
            NSSound.beep()
            return
        }
        let resolved = MarkdownLink.resolved(url, against: linkBaseURL)
        // A relative link in an untitled document has nowhere to go.
        if !MarkdownLink.open(resolved, scrollToAnchor: { scroll(toAnchor: $0) }) {
            NSSound.beep()
        }
    }

    private func scroll(toAnchor fragment: String) {
        guard let storage = textStorage,
              let location = MarkdownStyler.headingLocation(forFragment: fragment, in: storage.mutableString)
        else {
            NSSound.beep()
            return
        }
        scrollToTop(characterIndex: location)
    }

    /// Scrolls the line holding `index` to the top of the viewport.
    private func scrollToTop(characterIndex index: Int) {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
        else { return }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return }
        scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY + textContainerOrigin.y))
    }
}
