//
//  EditorTheme.swift
//  Tilde
//

import AppKit

/// Typography and layout tokens for the editor.
///
/// Colors are always macOS semantic colors; Tilde has no theme system.
/// Font-producing functions take the user's body size (⌘+/⌘-) as `size`.
nonisolated enum EditorTheme {
    /// Default body font size in points.
    static let defaultFontSize: CGFloat = 14

    /// Generous line height is the core of Tilde's readability.
    static let lineHeightMultiple: CGFloat = 1.5

    /// Horizontal and vertical breathing room around the text.
    static let padding: CGFloat = 28

    /// Markdown documents cap their content width so lines stay comfortable
    /// to read in a wide window. The measure is defined in type, not pixels
    /// — about 50 em of text (~100 Latin characters) plus the side padding
    /// — so it breathes like a book page and grows with ⌘+/⌘-. At the
    /// default 14 pt the column is ~756 px, close to Obsidian's 700 px.
    /// Plain text uses the full window width.
    static func maxContentWidth(for size: CGFloat) -> CGFloat {
        (size * 50).rounded() + 2 * padding
    }

    /// Body font: proportional (SF Pro) for Markdown, monospaced (SF Mono)
    /// for plain text.
    static func bodyFont(monospaced: Bool, size: CGFloat) -> NSFont {
        monospaced
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    static func lineSpacing(for font: NSFont) -> CGFloat {
        let lineHeight = font.ascender - font.descender + font.leading
        return ((lineHeightMultiple - 1) * lineHeight).rounded()
    }

    /// Line rhythm via `lineSpacing` (space between lines) rather than
    /// `lineHeightMultiple` (taller line boxes): a taller line box makes the
    /// insertion point 1.5× the text height, which looks wrong.
    static func paragraphStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing(for: font)
        return style
    }

    /// Empty lines carry their extra space as `paragraphSpacingBefore`
    /// instead of `lineSpacing`: TextKit 2 places lineSpacing above each
    /// line but swallows it INTO an empty line's line box (oversized caret,
    /// baseline hugging the previous line). spacingBefore keeps the
    /// baseline rhythm perfectly uniform and the caret text-height —
    /// verified empirically with a layout probe over all five spacing
    /// placements.
    static func emptyLineParagraphStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = lineSpacing(for: font)
        return style
    }

    /// The uniform attributes for body text.
    static func bodyAttributes(monospaced: Bool, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let font = bodyFont(monospaced: monospaced, size: size)
        return [
            .font: font,
            .paragraphStyle: paragraphStyle(for: font),
            .foregroundColor: NSColor.textColor,
        ]
    }

    /// Attributes for the insertion caret. Identical to `bodyAttributes`
    /// except the paragraph style is the empty-line one: when the document
    /// ends in a newline (or is empty), AppKit lays out an extra line
    /// fragment for the final caret position and — there being no character
    /// there — takes its height from `typingAttributes`, not from any
    /// paragraph style on the text. The regular style's `lineSpacing` sits
    /// inside that line box and makes the last caret taller than every other
    /// empty line's; the empty-line style keeps it text-height. A character
    /// the user actually types is restyled to the body style on the same
    /// edit, so this never leaks lineSpacing loss into real text.
    static func typingAttributes(monospaced: Bool, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let font = bodyFont(monospaced: monospaced, size: size)
        return [
            .font: font,
            .paragraphStyle: emptyLineParagraphStyle(for: font),
            .foregroundColor: NSColor.textColor,
        ]
    }

    // MARK: - Markdown styling tokens

    /// Syntax markers (`#`, `**`, `` ` ``…) stay visible but recede.
    static var markerColor: NSColor { .tertiaryLabelColor }

    static var quoteColor: NSColor { .secondaryLabelColor }

    /// The vertical bar drawn at the left edge of a rendered blockquote.
    static var quoteBarColor: NSColor { .tertiaryLabelColor }

    static var linkColor: NSColor { .linkColor }

    /// Subtle fill behind inline code and code blocks. In dark mode the
    /// quaternary fill all but vanishes against the window background, so
    /// the dark variant steps one level up.
    static let codeBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .tertiarySystemFill
            : .quaternarySystemFill
    }

    /// Marks a character range as belonging to a fenced code block so the
    /// editor can draw one unified background behind it (a per-character
    /// `.backgroundColor` would render as ragged per-line strips instead).
    static let codeBlockMarker = NSAttributedString.Key("tildeCodeBlock")

    /// Corner radius of the code-block background fill.
    static let codeCornerRadius: CGFloat = 5

    // MARK: - Syntax highlighting (JSON / YAML)

    /// Only keys are tinted — values and punctuation stay default, keeping
    /// highlighting quiet (PRODUCT.md §33.2). Comments recede like markers.
    static var syntaxKeyColor: NSColor { .systemBlue }

    static var syntaxCommentColor: NSColor { .tertiaryLabelColor }

    // MARK: - Code fence highlighting (preview only)

    /// A restrained, appearance-adaptive palette for code inside rendered
    /// Markdown fences. Comments recede; keyword/string/number get one quiet
    /// accent each — system colors pulled toward the text ink so they read
    /// as tinted ink on the grayscale page, not raw candy.
    static let codeKeywordColor: NSColor = inkBlended(.systemPurple, 0.3)
    static let codeStringColor: NSColor = inkBlended(.systemGreen, 0.45)
    static let codeNumberColor: NSColor = inkBlended(.systemBlue, 0.3)
    static var codeCommentColor: NSColor { .tertiaryLabelColor }

    private static func inkBlended(_ base: NSColor, _ fraction: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance {
                resolved = base.blended(withFraction: fraction, of: .textColor) ?? base
            }
            return resolved
        }
    }

    /// Code spans/blocks sit a point smaller so the monospaced face
    /// doesn't look oversized next to SF Pro.
    static func codeFont(size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }

    static func headingFont(level: Int, size: CGFloat) -> NSFont {
        switch level {
        case 1: .systemFont(ofSize: (size * 1.7).rounded(), weight: .bold)
        case 2: .systemFont(ofSize: (size * 1.45).rounded(), weight: .bold)
        case 3: .systemFont(ofSize: (size * 1.25).rounded(), weight: .bold)
        default: .systemFont(ofSize: (size * 1.05).rounded(), weight: .semibold)
        }
    }

    static func boldBodyFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }

    static func italicBodyFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(bodyFont(monospaced: false, size: size), toHaveTrait: .italicFontMask)
    }

    static func boldItalicBodyFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(boldBodyFont(size: size), toHaveTrait: .italicFontMask)
    }

    static func listMarkerFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    // MARK: - Line number gutter

    static var gutterFont: NSFont {
        .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    }

    static var gutterColor: NSColor { .tertiaryLabelColor }

    /// When the gutter is shown it provides the left reading margin, so the
    /// text view's own horizontal inset shrinks to a small gap beside the
    /// numbers instead of the full `padding`.
    static let gutterTextInset: CGFloat = 6
}
