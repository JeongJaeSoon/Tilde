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
/// paragraphs, headings, lists (including nesting and task-list
/// checkboxes), blockquotes, code blocks, thematic breaks, links, and
/// inline styles.
nonisolated struct MarkdownRenderer {
    var fontSize: CGFloat = EditorTheme.defaultFontSize

    /// Directory of the document being previewed, for resolving relative
    /// image AND link paths. Remote images are never fetched regardless.
    var baseURL: URL?

    /// Show every metadata row instead of folding the rest into "+N more";
    /// set once the reader clicks that line.
    var showsAllMetadataRows = false

    /// Metadata entries, by their index in the frontmatter, whose values
    /// show whole instead of cut; each joins once the reader clicks it.
    var wholeMetadataValues: Set<Int> = []

    /// What a click in the metadata header unfolds: the folded rows, or
    /// one cut value. Each arrives as a link Reader handles itself — it
    /// never leaves the app.
    enum MetadataUnfold: Equatable {
        case rows
        case value(Int)

        private static let prefix = "tilde-reader:unfold-"

        var link: URL {
            switch self {
            case .rows: URL(string: Self.prefix + "rows")!
            case .value(let index): URL(string: Self.prefix + "value-\(index)")!
            }
        }

        init?(link: URL) {
            let string = link.absoluteString
            guard string.hasPrefix(Self.prefix) else { return nil }
            let what = string.dropFirst(Self.prefix.count)
            if what == "rows" {
                self = .rows
            } else if what.hasPrefix("value-"), let index = Int(what.dropFirst("value-".count)) {
                self = .value(index)
            } else {
                return nil
            }
        }
    }

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

    /// A rendered document, and how its top differs from the source: the
    /// frontmatter's source characters don't render line for line — they
    /// become the metadata header, or nothing.
    struct Rendering {
        var text: NSAttributedString
        /// Source characters (UTF-16) of the frontmatter block, when it was
        /// turned into the header or hidden; 0 when the source maps straight on.
        var hiddenLength: Int
        /// Rendered characters in front of the body: the H1 made from
        /// `title:`, the metadata rows, and their rule.
        var prefixLength: Int
        /// The frontmatter's entries and whether a body follows them —
        /// enough for `metadataHeader(_:followedByBody:)` to rebuild the
        /// first `prefixLength` characters unfolded, without the body.
        var metadata: [MarkdownFrontmatter.Entry] = []
        var bodyFollows = false

        /// The editor reports its reading position as a fraction of the
        /// whole source. A position inside the frontmatter opens Reader at
        /// the very top, header in view; one in the body maps onto the body,
        /// past the header.
        func renderedFraction(forSourceFraction fraction: CGFloat, sourceLength: Int) -> CGFloat {
            guard hiddenLength > 0 else { return fraction }
            let hidden = CGFloat(hiddenLength)
            let offset = fraction * CGFloat(sourceLength)
            guard offset > hidden, text.length > 0 else { return 0 }
            let bodyFraction = (offset - hidden) / (CGFloat(sourceLength) - hidden)
            let prefix = CGFloat(prefixLength)
            let rendered = CGFloat(text.length)
            return (prefix + (rendered - prefix) * bodyFraction) / rendered
        }
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
        // Frontmatter becomes a quiet header at the top — `title:` as an H1,
        // the other keys as rows; the parser alone would show its fences as
        // rules and its keys as loose paragraphs. A block with nothing to show (empty, or
        // keys without values) is simply hidden, and one whose lines don't
        // all belong to keys appears raw as a code listing — never dropped.
        var markdown = source
        var hiddenLength = 0
        var metadata: [MarkdownFrontmatter.Entry] = []
        let nsSource = source as NSString
        if let frontmatter = MarkdownFrontmatter.range(in: nsSource) {
            let body = nsSource.substring(from: NSMaxRange(frontmatter))
            let hasBody = body.contains { !$0.isWhitespace }
            switch MarkdownFrontmatter.entries(in: nsSource, block: frontmatter) {
            case let entries? where !entries.isEmpty:
                metadata = entries
                markdown = body
                hiddenLength = frontmatter.length
            case .some where hasBody:
                markdown = body
                hiddenLength = frontmatter.length
            default:
                // Unreadable metadata, or an empty block with no body (an
                // empty page would read as a failed render): the block itself.
                let listing = Self.codeListing(nsSource.substring(with: frontmatter))
                markdown = hasBody ? listing + "\n" + body : listing
            }
        }

        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            // The parser should never throw under this policy, but never
            // fail to show something: fall back to plain body text, under
            // the header.
            let bodyFollows = markdown.contains { !$0.isWhitespace }
            let text = NSMutableAttributedString(attributedString: metadataHeader(metadata, followedByBody: bodyFollows))
            let prefixLength = text.length
            text.append(NSAttributedString(
                string: markdown,
                attributes: EditorTheme.bodyAttributes(monospaced: false, size: fontSize)
            ))
            return Rendering(text: text, hiddenLength: hiddenLength, prefixLength: prefixLength, metadata: metadata, bodyFollows: bodyFollows)
        }
        let built = build(from: parsed, metadata: metadata)
        return Rendering(text: built.text, hiddenLength: hiddenLength, prefixLength: built.prefixLength, metadata: metadata, bodyFollows: built.bodyFollows)
    }

    /// Metadata rows, at most this many before the rest fold into one
    /// "+N more" line — a header, not a second document. Clicking the line
    /// shows the other rows.
    static let metadataRowLimit = 5

    /// A value longer than this many lines or characters is cut, so one
    /// long description can't fill the screen either; a quiet "more" after
    /// the cut shows that value whole.
    static let metadataValueLineLimit = 3
    static let metadataValueCharacterLimit = 240

    /// The frontmatter header: `title:` as an H1, the other keys as rows,
    /// and the rule that closes it when a body follows. Reader splices a
    /// rebuilt one over the first `prefixLength` characters to unfold rows
    /// or values without rendering the body again.
    func metadataHeader(_ metadata: [MarkdownFrontmatter.Entry], followedByBody: Bool) -> NSAttributedString {
        let header = NSMutableAttributedString()
        // Rows keep their index in the frontmatter: it names the value a
        // cut value's link unfolds.
        var rows = Array(metadata.enumerated())
        if let titleRow = rows.firstIndex(where: { !$0.element.isRaw && $0.element.key.lowercased() == "title" }) {
            let title = rows.remove(at: titleRow).element.value.replacingOccurrences(of: "\n", with: " ")
            let heading = PresentationIntent(.header(level: 1), identity: -1, parent: nil)
            var noAnchors: Set<String> = []
            append(Block(intent: heading, runs: [(title, nil, nil, nil)], takesAnchor: false), to: header, isFirst: true, usedAnchors: &noAnchors)
        }
        guard !rows.isEmpty else { return header }
        appendMetadataRows(rows, to: header)
        // The closing fence, dissolved: the same hairline as a `---` rule.
        if followedByBody { appendThematicBreak(to: header) }
        return header
    }

    /// The frontmatter's rows: key, tab, value — the editor's lines with
    /// the syntax dissolved. Keys sit in the quote color and values in the
    /// label color, a point smaller than body text. A one-line row keeps
    /// the page's line rhythm; a long value's wrapped lines sit tighter
    /// and align under the value column, so they read as one value.
    private func appendMetadataRows(_ rows: [(offset: Int, element: MarkdownFrontmatter.Entry)], to result: NSMutableAttributedString) {
        // A lone extra row is shown rather than folded into "+1 more".
        let folds = !showsAllMetadataRows && rows.count > Self.metadataRowLimit + 1
        let shown = folds ? Array(rows.prefix(Self.metadataRowLimit)) : rows
        let font = EditorTheme.bodyFont(monospaced: false, size: fontSize - 1)
        let rawFont = EditorTheme.codeFont(size: fontSize - 1)
        // Measured over every row, folded or not, so unfolding doesn't
        // shift the column under the rows already on screen. Values line up
        // one em past the widest key, capped so a long key can't squeeze
        // the values into a sliver (it just pushes its own value along).
        let widest = rows.map { ($0.element.key as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let valueColumn = min(widest + font.pointSize, contentWidth * 0.4).rounded(.up)

        // Each value line is its own paragraph — real newlines, so copied
        // text reads right — indented to the value column. Only a row's
        // last line takes the row spacing, so a value's lines sit together
        // at the tighter wrapped-line rhythm.
        let halfBeat = EditorTheme.lineSpacing(for: font) / 2
        func style(firstLine: Bool, lastLine: Bool) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = halfBeat
            style.paragraphSpacing = lastLine ? halfBeat : 0
            style.tabStops = [NSTextTab(textAlignment: .left, location: valueColumn)]
            style.defaultTabInterval = font.pointSize
            style.headIndent = valueColumn
            style.firstLineHeadIndent = firstLine ? 0 : valueColumn
            return style
        }

        for (index, row) in shown {
            // Tabs would jump to the row's tab stops; they're spacing here.
            var value = row.value.replacingOccurrences(of: "\t", with: " ")
            let cut = wholeMetadataValues.contains(index) ? nil : Self.cutValue(value)
            if let cut { value = cut }
            let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: row.isRaw ? rawFont : font,
                .foregroundColor: row.isRaw ? EditorTheme.quoteColor : NSColor.labelColor,
            ]

            let rowStart = result.length
            result.append(NSAttributedString(string: row.key + "\t", attributes: [
                .font: font,
                .foregroundColor: EditorTheme.quoteColor,
            ]))
            for (lineIndex, line) in lines.enumerated() {
                let lineStart = lineIndex == 0 ? rowStart : result.length
                result.append(NSAttributedString(string: String(line), attributes: valueAttributes))
                if cut != nil, lineIndex == lines.count - 1 {
                    // After a cut, a quiet "more" — the same gray and word
                    // as "+N more" — is the one place to click; the value
                    // itself stays plain text.
                    result.append(NSAttributedString(string: " ", attributes: [.font: font]))
                    result.append(NSAttributedString(string: String(localized: "more"), attributes: [
                        .font: font,
                        .foregroundColor: EditorTheme.quoteColor,
                        .link: MetadataUnfold.value(index).link,
                    ]))
                }
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                result.addAttribute(
                    .paragraphStyle,
                    value: style(firstLine: lineIndex == 0, lastLine: lineIndex == lines.count - 1),
                    range: NSRange(location: lineStart, length: result.length - lineStart)
                )
            }
        }
        if folds {
            // A link — the pointing hand and VoiceOver treat it as one — set
            // as quietly as the keys, so the header stays grayscale.
            let start = result.length
            result.append(NSAttributedString(string: String(localized: "+\(Int(rows.count - shown.count)) more"), attributes: [
                .font: font,
                .foregroundColor: EditorTheme.quoteColor,
                .link: MetadataUnfold.rows.link,
            ]))
            result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            result.addAttribute(.paragraphStyle, value: style(firstLine: true, lastLine: true), range: NSRange(location: start, length: result.length - start))
        }
    }

    /// `value` cut to a few lines and characters, or nil when it fits. A
    /// cut ends at a sentence end when one is near the limit — no ellipsis
    /// needed — and otherwise between words, trailing punctuation dropped
    /// before the "…" so a period never runs into it ("....").
    static func cutValue(_ value: String) -> String? {
        var lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        var cut = lines.count > metadataValueLineLimit
        if cut { lines = Array(lines.prefix(metadataValueLineLimit)) }
        var text = lines.joined(separator: "\n")
        if text.count > metadataValueCharacterLimit {
            let limit = text.index(text.startIndex, offsetBy: metadataValueCharacterLimit)
            let near = text.index(text.startIndex, offsetBy: metadataValueCharacterLimit * 3 / 5)
            if let sentenceEnd = text[near..<limit].indices.last(where: { isSentenceEnd(at: $0, in: text) }) {
                text = String(text[...sentenceEnd])
            } else {
                var end = limit
                if let space = text[..<limit].lastIndex(where: { $0 == " " || $0 == "\n" }),
                   text.distance(from: space, to: limit) < 30 {
                    end = space
                }
                text = String(text[..<end])
            }
            cut = true
        }
        guard cut else { return nil }
        text = text.trimmingCharacters(in: .whitespaces)
        if let last = text.indices.last, isSentenceEnd(at: last, in: text) { return text }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:、，；：").union(.whitespaces)) + "…"
    }

    /// `.`, `!`, or `?` followed by whitespace or the end — so "v1.2" and
    /// "example.com" don't count — or a CJK full stop, which needs no space.
    private static func isSentenceEnd(at index: String.Index, in text: String) -> Bool {
        let character = text[index]
        if "。！？".contains(character) { return true }
        guard ".!?".contains(character) else { return false }
        let next = text.index(after: index)
        return next == text.endIndex || text[next].isWhitespace
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
        /// False for the H1 made from `title:`: it isn't a heading in the
        /// Markdown, so it mustn't claim a slug a body heading's
        /// `#fragment` links expect (GitHub never sees it either).
        var takesAnchor = true
        /// True for a list item's first block when it sits directly in the
        /// item — the only place a task-list `[ ]` / `[x]` counts. A later
        /// paragraph of the same item, or one inside a quote in it, is text.
        var opensListItem = false
    }

    private func build(from parsed: AttributedString, metadata: [MarkdownFrontmatter.Entry]) -> (text: NSAttributedString, prefixLength: Int, bodyFollows: Bool) {
        // Group runs into leaf blocks by the identity of their innermost
        // presentation-intent component.
        var blocks: [Block] = []
        var previousLeafIdentity: Int?
        // List items whose first block has gone by, innermost item per block.
        var seenListItems: Set<Int> = []
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let leafIdentity = intent?.components.first?.identity
            if blocks.isEmpty || leafIdentity != previousLeafIdentity {
                var block = Block(intent: intent)
                let components = intent?.components ?? []
                if let item = components.first(where: { if case .listItem = $0.kind { return true }; return false }) {
                    let isFirst = seenListItems.insert(item.identity).inserted
                    block.opensListItem = isFirst && components.dropFirst().first?.identity == item.identity
                }
                blocks.append(block)
            }
            previousLeafIdentity = leafIdentity
            blocks[blocks.count - 1].runs.append((text, run.inlinePresentationIntent, run.link, run.imageURL))
        }

        // The frontmatter renders where it stands, at the top; the body
        // follows exactly as written, its own H1 included.
        let header = metadataHeader(metadata, followedByBody: !blocks.isEmpty)
        let result = NSMutableAttributedString(attributedString: header)
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
            append(block, to: result, isFirst: result.length == 0, extraSpacingBefore: afterTextBlock, usedAnchors: &usedAnchors)
            afterTextBlock = usesTextBlock(block)
            index += 1
        }
        return (result, header.length, !blocks.isEmpty)
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

        // A task item's `[ ]` / `[x]` becomes its marker; the text after it
        // starts the item.
        var runs = block.runs
        let taskDone = Self.taskState(of: block)
        if taskDone != nil {
            runs[0].text = String(runs[0].text.dropFirst(Self.taskMarkerLength).drop { $0 == " " || $0 == "\t" })
        }

        // List / prefix marker.
        var markerLength = 0
        if let done = taskDone {
            // In place of the bullet or number, before the same tab stop,
            // so wrapped lines still align under the text.
            let marker = NSMutableAttributedString(attributedString: checkbox(done: done))
            marker.append(NSAttributedString(string: "\t", attributes: [.font: EditorTheme.listMarkerFont(size: fontSize)]))
            result.append(marker)
            markerLength = marker.length
        } else if let ordered = listOrdered {
            let marker = ordered ? "\(listOrdinal ?? 1).\t" : "•\t"
            result.append(NSAttributedString(string: marker, attributes: [
                .font: EditorTheme.listMarkerFont(size: fontSize),
                .foregroundColor: NSColor.textColor,
            ]))
            markerLength = (marker as NSString).length
        }

        // Body runs with inline styling. A done item's text recedes so the
        // open ones stand out; its links keep their color.
        let ink = taskDone == true ? EditorTheme.quoteColor : NSColor.textColor
        for run in runs {
            result.append(inlineAttributed(run, baseFont: baseFont, color: ink))
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
        if headerLevel > 0, block.takesAnchor {
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

    // MARK: - Task lists

    /// `[ ] `, `[x] `, and `[X] ` are all four characters.
    private static let taskMarkerLength = 4

    /// Whether a task item is done, from the `[ ] ` / `[x] ` / `[X] ` that
    /// opens its first paragraph, or nil for any other block. Apple's
    /// parser has no task-list extension and hands the marker through as
    /// text, so it must open a plain run: `` `[ ]` `` and `[link](url)`
    /// stay what they are, and so do `[ x]`, `[]`, and `[x]` with no space.
    private static func taskState(of block: Block) -> Bool? {
        guard block.opensListItem,
              case .paragraph = block.intent?.components.first?.kind,
              let first = block.runs.first,
              first.inline == nil, first.link == nil, first.image == nil
        else { return nil }
        if first.text.hasPrefix("[ ] ") { return false }
        if first.text.hasPrefix("[x] ") || first.text.hasPrefix("[X] ") { return true }
        return nil
    }

    /// Room kept between a checkbox and its item's text at large sizes,
    /// where the box would otherwise outgrow the marker column.
    private static let checkboxGap: CGFloat = 5

    /// The checkbox in place of a task item's bullet: SF Symbols' square,
    /// checked when done, in the bullet's ink or — done — the quote color.
    /// It takes the text's size and sits centered on the cap height, so the
    /// line is exactly as tall as a bullet's; at large sizes it stays
    /// inside the marker column so the text still starts at the tab stop.
    /// Like images and rules, it copies as an attachment character.
    private func checkbox(done: Bool) -> NSAttributedString {
        let color = done ? EditorTheme.quoteColor : NSColor.textColor
        let markerFont = EditorTheme.listMarkerFont(size: fontSize)
        // A palette color, not a template tint: TextKit 1 draws template
        // attachments black, unreadable in dark mode.
        let configuration = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(
            systemSymbolName: done ? "checkmark.square" : "square",
            accessibilityDescription: done ? String(localized: "Done") : String(localized: "Not done")
        )?.withSymbolConfiguration(configuration) else {
            return NSAttributedString(string: done ? "☑" : "☐", attributes: [.font: markerFont, .foregroundColor: color])
        }

        var size = image.size
        let maxWidth = indentUnit - Self.checkboxGap
        if size.width > maxWidth {
            size = NSSize(width: maxWidth, height: (size.height * maxWidth / size.width).rounded())
        }
        let capHeight = EditorTheme.bodyFont(monospaced: false, size: fontSize).capHeight
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: ((capHeight - size.height) / 2).rounded(), width: size.width, height: size.height)
        let box = NSMutableAttributedString(attachment: attachment)
        box.addAttribute(.font, value: markerFont, range: NSRange(location: 0, length: box.length))
        return box
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
        baseFont: NSFont,
        color: NSColor = .textColor
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
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.link] = resolvedLink(link)
        } else {
            attributes[.foregroundColor] = color
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
                .underlineStyle: NSUnderlineStyle.single.rawValue,
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
