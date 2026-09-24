//
//  MarkdownRenderer.swift
//  Tilde
//

import AppKit

/// Renders Markdown source into a styled `NSAttributedString` for the
/// read-only Preview mode (⌘⇧P).
///
/// Apple's `AttributedString(markdown:, .full)` parser identifies block
/// structure as `PresentationIntent` metadata but applies no visual
/// styling; this renderer walks that metadata and builds the styled text
/// using the same `EditorTheme` tokens as the editor, so toggling into
/// Preview reads as the syntax markers dissolving rather than a different
/// app.
///
/// Tables and images are handled in later milestones; this milestone covers
/// paragraphs, headings, lists (including nesting), blockquotes, code
/// blocks, thematic breaks, links, and inline styles.
nonisolated struct MarkdownRenderer {
    var fontSize: CGFloat = EditorTheme.defaultFontSize

    /// Directory of the document being previewed, for resolving relative
    /// image AND link paths. Remote images are never fetched regardless.
    var baseURL: URL?

    /// Marks each rendered heading with its GitHub-style anchor slug, so a
    /// clicked `#fragment` link can jump to the matching heading.
    static let headingAnchorKey = NSAttributedString.Key("tildeHeadingAnchor")

    /// GitHub-style anchor slug for a heading: lowercased, spaces become
    /// hyphens, and everything but letters, digits, `-`, and `_` is
    /// dropped. Applied to link fragments too, so `#Section Title` and
    /// `#section-title` both reach the same heading.
    static func anchorSlug(for text: String) -> String {
        var slug = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                slug.append(scalar)
            } else if scalar == " " {
                slug.append("-")
            }
        }
        return String(slug)
    }

    /// A rendered document and how many source characters (UTF-16) were
    /// hidden in front of it — the frontmatter block, when one was dropped.
    struct Rendering {
        var text: NSAttributedString
        var hiddenLength: Int
    }

    /// The editor reports its reading position as a fraction of the whole
    /// source, but the rendered text starts after the hidden frontmatter:
    /// shift the fraction past it, so a position inside the metadata opens
    /// Reader at the top.
    static func renderedFraction(_ sourceFraction: CGFloat, hiddenLength: Int, sourceLength: Int) -> CGFloat {
        guard hiddenLength > 0 else { return sourceFraction }
        guard sourceLength > hiddenLength else { return 0 }
        let hidden = CGFloat(hiddenLength)
        let total = CGFloat(sourceLength)
        return max(0, (sourceFraction * total - hidden) / (total - hidden))
    }

    /// Indentation added per list-nesting level and for blockquotes.
    private let indentUnit: CGFloat = 22

    /// Rendered content width (matches the editor's centered column).
    private var contentWidth: CGFloat { EditorTheme.maxContentWidth(for: fontSize) - 2 * EditorTheme.padding }

    // MARK: - Entry point

    func render(_ source: String) -> NSAttributedString {
        renderDocument(source).text
    }

    func renderDocument(_ source: String) -> Rendering {
        // Frontmatter is hidden, not rendered: the parser would show its
        // fences as rules and its keys as loose paragraphs. The metadata
        // stays editable in the editor. A metadata card above the content
        // is the upgrade if readers turn out to want a title or date shown.
        var markdown = source
        var hiddenLength = 0
        let nsSource = source as NSString
        if let frontmatter = MarkdownFrontmatter.range(in: nsSource) {
            let body = nsSource.substring(from: NSMaxRange(frontmatter))
            if body.contains(where: { !$0.isWhitespace }) {
                markdown = body
                hiddenLength = frontmatter.length
            } else {
                // Nothing but metadata (a SKILL.md, a Hugo _index.md): an
                // empty page would read as a failed render, so show the
                // block itself as a quiet code listing.
                markdown = Self.codeListing(nsSource.substring(with: frontmatter))
            }
        }

        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            // The parser should never throw under this policy, but never
            // fail to show something: fall back to plain body text.
            return Rendering(
                text: NSAttributedString(
                    string: markdown,
                    attributes: EditorTheme.bodyAttributes(monospaced: false, size: fontSize)
                ),
                hiddenLength: hiddenLength
            )
        }
        return Rendering(text: build(from: parsed), hiddenLength: hiddenLength)
    }

    /// `text` as a fenced YAML listing, with a fence longer than any
    /// backtick run inside it.
    private static func codeListing(_ text: String) -> String {
        var fence = "```"
        while text.contains(fence) { fence += "`" }
        let body = text.hasSuffix("\n") ? text : text + "\n"
        return fence + "yaml\n" + body + fence + "\n"
    }

    // MARK: - Block grouping

    /// A leaf block (paragraph, heading, code block, …) with its runs.
    private struct Block {
        var intent: PresentationIntent?
        var runs: [(text: String, inline: InlinePresentationIntent?, link: URL?, image: URL?)] = []
    }

    private func build(from parsed: AttributedString) -> NSAttributedString {
        // Group runs into leaf blocks by the identity of their innermost
        // presentation-intent component.
        var blocks: [Block] = []
        var previousLeafIdentity: Int?
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let leafIdentity = intent?.components.first?.identity
            if blocks.isEmpty || leafIdentity != previousLeafIdentity {
                blocks.append(Block(intent: intent))
            }
            previousLeafIdentity = leafIdentity
            blocks[blocks.count - 1].runs.append((text, run.inlinePresentationIntent, run.link, run.imageURL))
        }

        let result = NSMutableAttributedString()
        var index = 0
        var afterTextBlock = false
        // Slugs already assigned to headings, so duplicates get "-1", "-2"…
        // suffixes the way GitHub disambiguates them. A set (not a counter)
        // so a suffixed slug can never collide with a heading that slugs to
        // the same text naturally ("Foo", "Foo", "Foo 1").
        var usedAnchors: Set<String> = []
        while index < blocks.count {
            let block = blocks[index]
            if let tableID = tableIdentity(of: block.intent) {
                // Consume every block belonging to this table.
                var tableBlocks: [Block] = []
                while index < blocks.count, tableIdentity(of: blocks[index].intent) == tableID {
                    tableBlocks.append(blocks[index])
                    index += 1
                }
                if afterTextBlock { appendBlockSpacer(to: result) }
                appendTable(tableBlocks, to: result, isFirst: result.length == 0)
                afterTextBlock = true
                continue
            }
            // NSTextBlock layout (tables, quotes, code) swallows the
            // paragraph's own paragraphSpacing, so the gap below any such
            // block is added as leading space on the block that follows it —
            // the page keeps one uniform vertical beat. Between two text
            // blocks even that leading space is absorbed INSIDE the second
            // block, so those adjacencies get a real spacer paragraph.
            if afterTextBlock, usesTextBlock(block) { appendBlockSpacer(to: result) }
            append(block, to: result, isFirst: index == 0, extraSpacingBefore: afterTextBlock, usedAnchors: &usedAnchors)
            afterTextBlock = usesTextBlock(block)
            index += 1
        }
        return result
    }

    /// An invisible paragraph exactly one beat tall, placed between two
    /// text-block paragraphs (quote/code/table), where paragraph spacing —
    /// leading or trailing — is absorbed by the block layout.
    private func appendBlockSpacer(to result: NSMutableAttributedString) {
        let beat = EditorTheme.lineSpacing(for: EditorTheme.bodyFont(monospaced: false, size: fontSize))
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = beat
        style.maximumLineHeight = beat
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 1),
            .paragraphStyle: style,
        ]))
    }

    /// True for blocks laid out with an NSTextBlock (top-level quotes and
    /// code listings), whose trailing paragraphSpacing TextKit swallows.
    private func usesTextBlock(_ block: Block) -> Bool {
        let components = block.intent?.components ?? []
        if case .codeBlock = components.first?.kind { return true }
        let isQuote = components.contains { if case .blockQuote = $0.kind { return true }; return false }
        let inList = components.contains {
            if case .orderedList = $0.kind { return true }
            if case .unorderedList = $0.kind { return true }
            return false
        }
        return isQuote && !inList
    }

    // MARK: - Tables

    private func tableIdentity(of intent: PresentationIntent?) -> Int? {
        intent?.components.first(where: { if case .table = $0.kind { return true }; return false })?.identity
    }

    private func appendTable(_ blocks: [Block], to result: NSMutableAttributedString, isFirst: Bool) {
        // Column geometry from the shared table intent.
        var columns: [PresentationIntent.TableColumn] = []
        for component in blocks.first?.intent?.components ?? [] {
            if case .table(let cols) = component.kind { columns = cols }
        }
        let columnCount = max(columns.count, 1)

        let table = NSTextTable()
        table.numberOfColumns = columnCount

        let blockStart = result.length
        for cell in blocks {
            var column = 0
            var row = 0
            var isHeader = false
            for component in cell.intent?.components ?? [] {
                switch component.kind {
                case .tableCell(let c): column = c
                case .tableHeaderRow: isHeader = true; row = 0
                case .tableRow(let ordinal): row = ordinal
                default: break
                }
            }

            let tableBlock = NSTextTableBlock(
                table: table, startingRow: row, rowSpan: 1,
                startingColumn: column, columnSpan: 1
            )
            tableBlock.setBorderColor(.separatorColor)
            tableBlock.setWidth(1, type: .absoluteValueType, for: .border)
            tableBlock.setWidth(6, type: .absoluteValueType, for: .padding)

            let style = NSMutableParagraphStyle()
            style.textBlocks = [tableBlock]
            style.alignment = alignment(for: column, in: columns)

            let baseFont = isHeader
                ? EditorTheme.boldBodyFont(size: fontSize)
                : EditorTheme.bodyFont(monospaced: false, size: fontSize)

            let cellStart = result.length
            for run in cell.runs {
                result.append(inlineAttributed(run, baseFont: baseFont))
            }
            result.append(NSAttributedString(string: "\n"))
            result.addAttribute(.paragraphStyle,
                                value: style,
                                range: NSRange(location: cellStart, length: result.length - cellStart))
        }
        _ = (blockStart, isFirst)
    }

    private func alignment(for column: Int, in columns: [PresentationIntent.TableColumn]) -> NSTextAlignment {
        guard column < columns.count else { return .left }
        switch columns[column].alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        @unknown default: return .left
        }
    }

    // MARK: - Block rendering

    private func append(_ block: Block, to result: NSMutableAttributedString, isFirst: Bool, extraSpacingBefore: Bool = false, usedAnchors: inout Set<String>) {
        let components = block.intent?.components ?? []
        let leafKind = components.first?.kind

        switch leafKind {
        case .thematicBreak:
            appendThematicBreak(to: result)
            return
        case .codeBlock(let language):
            appendCodeBlock(block, language: language, to: result)
            return
        default:
            break
        }

        // Header level, if any.
        var headerLevel = 0
        for component in components {
            if case .header(let level) = component.kind { headerLevel = level }
        }

        // List context: the nearest list container defines the marker; the
        // count of list containers is the nesting depth.
        var listOrdinal: Int?
        var listOrdered: Bool?
        var listDepth = 0
        for component in components {
            switch component.kind {
            case .listItem(let ordinal):
                if listOrdinal == nil { listOrdinal = ordinal }
            case .orderedList:
                if listOrdered == nil { listOrdered = true }
                listDepth += 1
            case .unorderedList:
                if listOrdered == nil { listOrdered = false }
                listDepth += 1
            default:
                break
            }
        }

        let isQuote = components.contains { if case .blockQuote = $0.kind { return true }; return false }

        // Base font for this block's body runs.
        let baseFont: NSFont = headerLevel > 0
            ? EditorTheme.headingFont(level: headerLevel, size: fontSize)
            : EditorTheme.bodyFont(monospaced: false, size: fontSize)

        let blockStart = result.length

        // List / prefix marker.
        var markerLength = 0
        if let ordered = listOrdered {
            let marker = ordered ? "\(listOrdinal ?? 1).\t" : "•\t"
            result.append(NSAttributedString(string: marker, attributes: [
                .font: EditorTheme.listMarkerFont(size: fontSize),
                .foregroundColor: NSColor.textColor,
            ]))
            markerLength = (marker as NSString).length
        }

        // Body runs with inline styling.
        for run in block.runs {
            result.append(inlineAttributed(run, baseFont: baseFont))
        }
        result.append(NSAttributedString(string: "\n"))

        // Paragraph style for the whole block.
        let style = NSMutableParagraphStyle()
        style.lineSpacing = EditorTheme.lineSpacing(for: baseFont)
        style.paragraphSpacing = EditorTheme.lineSpacing(for: baseFont)
        if !isFirst {
            if headerLevel > 0 {
                style.paragraphSpacingBefore = EditorTheme.lineSpacing(for: baseFont) * 1.5
            } else if extraSpacingBefore, !(isQuote && listDepth == 0) {
                style.paragraphSpacingBefore = EditorTheme.lineSpacing(for: baseFont)
            }
        }

        let listIndent = CGFloat(listDepth) * indentUnit
        if listDepth > 0 {
            let quoteIndent = isQuote ? indentUnit : 0
            style.firstLineHeadIndent = CGFloat(listDepth - 1) * indentUnit + quoteIndent
            style.headIndent = listIndent + quoteIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent + quoteIndent)]
        }
        // Blockquote: a quiet left bar with padding, via a text block.
        if isQuote, listDepth == 0 {
            let quoteBlock = NSTextBlock()
            quoteBlock.setValue(100, type: .percentageValueType, for: .width)
            quoteBlock.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
            quoteBlock.setBorderColor(EditorTheme.quoteBarColor, for: .minX)
            quoteBlock.setWidth(indentUnit, type: .absoluteValueType, for: .padding, edge: .minX)
            style.textBlocks = [quoteBlock]
        }

        let blockRange = NSRange(location: blockStart, length: result.length - blockStart)
        result.addAttribute(.paragraphStyle, value: style, range: blockRange)

        // Tag headings with their anchor slug for `#fragment` navigation.
        if headerLevel > 0 {
            let base = Self.anchorSlug(for: block.runs.map(\.text).joined())
            var slug = base
            var suffix = 1
            while usedAnchors.contains(slug) {
                slug = "\(base)-\(suffix)"
                suffix += 1
            }
            usedAnchors.insert(slug)
            result.addAttribute(Self.headingAnchorKey, value: slug, range: blockRange)
        }
        _ = markerLength
    }

    private func appendCodeBlock(_ block: Block, language: String?, to result: NSMutableAttributedString) {
        let blockStart = result.length
        var text = block.runs.map(\.text).joined()
        // The parser keeps a trailing newline inside the code block; drop it
        // so the block separator is the only gap after.
        if text.hasSuffix("\n") { text.removeLast() }

        let codeStart = result.length
        result.append(NSAttributedString(string: text, attributes: [
            .font: EditorTheme.codeFont(size: fontSize),
            .foregroundColor: NSColor.textColor,
        ]))

        // Generic lexical highlighting of the listing (comments, strings,
        // numbers, keywords) — tinting only, the mono font is unchanged.
        for span in CodeHighlighter().spans(for: text, language: language) {
            let range = NSRange(location: codeStart + span.range.location, length: span.range.length)
            result.addAttribute(.foregroundColor, value: span.color, range: range)
        }

        result.append(NSAttributedString(string: "\n"))

        // One block behind the whole listing (a text block, like a table
        // cell) instead of a ragged per-line background. The fill itself is
        // NOT the text block's square background: the range is tagged with
        // codeBlockMarker and the Reader's text view draws one rounded band.
        let codeBlock = NSTextBlock()
        codeBlock.setValue(100, type: .percentageValueType, for: .width)
        codeBlock.setWidth(Self.codeBlockPadding, type: .absoluteValueType, for: .padding)

        let style = NSMutableParagraphStyle()
        style.textBlocks = [codeBlock]
        style.lineSpacing = EditorTheme.lineSpacing(for: EditorTheme.codeFont(size: fontSize))
        style.paragraphSpacing = EditorTheme.lineSpacing(for: EditorTheme.bodyFont(monospaced: false, size: fontSize))
        let blockRange = NSRange(location: blockStart, length: result.length - blockStart)
        result.addAttribute(.paragraphStyle, value: style, range: blockRange)
        result.addAttribute(EditorTheme.codeBlockMarker, value: true, range: blockRange)
    }

    /// Inner padding of the code listing's text block; the Reader text view
    /// outsets its rounded fill by the same amount to cover it.
    static let codeBlockPadding: CGFloat = 10

    private func appendThematicBreak(to result: NSMutableAttributedString) {
        let width = contentWidth
        let image = NSImage(size: NSSize(width: width, height: 1))
        image.lockFocus()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: 1).fill()
        image.unlockFocus()

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 0, width: width, height: 1)

        let blockStart = result.length
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "\n"))

        let style = NSMutableParagraphStyle()
        let bodyFont = EditorTheme.bodyFont(monospaced: false, size: fontSize)
        style.paragraphSpacing = EditorTheme.lineSpacing(for: bodyFont)
        style.paragraphSpacingBefore = EditorTheme.lineSpacing(for: bodyFont)
        result.addAttribute(.paragraphStyle,
                            value: style,
                            range: NSRange(location: blockStart, length: result.length - blockStart))
    }

    // MARK: - Inline rendering

    private func inlineAttributed(
        _ run: (text: String, inline: InlinePresentationIntent?, link: URL?, image: URL?),
        baseFont: NSFont
    ) -> NSAttributedString {
        if let image = run.image {
            return imageAttributed(altText: run.text, url: image)
        }

        var attributes: [NSAttributedString.Key: Any] = [:]
        let inline = run.inline

        if inline?.contains(.code) == true {
            attributes[.font] = EditorTheme.codeFont(size: baseFont.pointSize)
            attributes[.backgroundColor] = EditorTheme.codeBackgroundColor
        } else {
            attributes[.font] = styledFont(base: baseFont, inline: inline)
        }

        if inline?.contains(.strikethrough) == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if let link = run.link {
            attributes[.foregroundColor] = EditorTheme.linkColor
            attributes[.link] = resolvedLink(link)
        } else {
            attributes[.foregroundColor] = NSColor.textColor
        }

        return NSAttributedString(string: run.text, attributes: attributes)
    }

    /// Where a click on this link should actually go. The parser hands
    /// relative targets through nearly verbatim, and NSTextView can't open
    /// those — so `README.ko.md` silently did nothing. Scheme'd URLs pass
    /// through, relative paths resolve against the document's directory
    /// into file URLs, and fragment-only links stay as-is for the Reader
    /// view to turn into in-document jumps.
    private func resolvedLink(_ url: URL) -> URL {
        if url.scheme != nil { return url }
        let path = url.relativePath
        guard !path.isEmpty else { return url }  // "#fragment" — in-document
        var resolved: URL
        if path.hasPrefix("/") {
            resolved = URL(fileURLWithPath: path)
        } else if let baseURL {
            // appendingPathComponent handles embedded subdirectories;
            // standardizing collapses "./" and "../" segments.
            resolved = baseURL.appendingPathComponent(path).standardizedFileURL
        } else {
            return url
        }
        if let fragment = url.fragment,
           var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            components.fragment = fragment
            resolved = components.url ?? resolved
        }
        return resolved
    }

    /// A local image as a scaled attachment; anything not loadable (remote,
    /// missing, or sandbox-denied) falls back to its alt text.
    private func imageAttributed(altText rawAltText: String, url: URL) -> NSAttributedString {
        // `![](x.png)` — an image with no alt — arrives from the Markdown
        // parser as U+FFFC (the object-replacement character), not as an
        // empty run, so strip it or the fallbacks below never trigger.
        let altText = rawAltText
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Never fetch remote images (privacy §30) — show alt text as a link.
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return NSAttributedString(string: altText.isEmpty ? url.absoluteString : altText, attributes: [
                .font: EditorTheme.bodyFont(monospaced: false, size: fontSize),
                .foregroundColor: EditorTheme.linkColor,
                .link: url,
            ])
        }

        // Resolve relative paths against the document's directory.
        // appendingPathComponent treats baseURL as a directory regardless of
        // a trailing slash, and handles embedded subdirectories.
        let resolved: URL
        if url.scheme != nil {
            resolved = url
        } else if let baseURL {
            resolved = baseURL.appendingPathComponent(url.relativePath)
        } else {
            resolved = url
        }

        if resolved.isFileURL, let image = NSImage(contentsOf: resolved) {
            let natural = image.size
            let width = min(natural.width, contentWidth)
            let scale = natural.width > 0 ? width / natural.width : 1
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: 0, width: width, height: natural.height * scale)
            return NSAttributedString(attachment: attachment)
        }

        // Missing / unreadable: quiet alt-text placeholder.
        let label = altText.isEmpty ? String(localized: "(image)") : altText
        return NSAttributedString(string: "🖼 \(label)", attributes: [
            .font: EditorTheme.bodyFont(monospaced: false, size: fontSize),
            .foregroundColor: EditorTheme.quoteColor,
        ])
    }

    private func styledFont(base: NSFont, inline: InlinePresentationIntent?) -> NSFont {
        guard let inline else { return base }
        var font = base
        let manager = NSFontManager.shared
        if inline.contains(.stronglyEmphasized) {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if inline.contains(.emphasized) {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}
