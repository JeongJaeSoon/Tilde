// CLI test runner for MarkdownStyler: style an NSTextStorage, assert attributes.

import AppKit

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("  ok  \(name)") }
    else { failed += 1; print("FAIL  \(name)") }
}

func styled(_ markdown: String) -> NSTextStorage {
    let storage = NSTextStorage(string: markdown)
    let styler = MarkdownStyler()
    styler.restyleAll(storage)
    return storage
}

func font(_ storage: NSTextStorage, at location: Int) -> NSFont? {
    storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
}
func color(_ storage: NSTextStorage, at location: Int) -> NSColor? {
    storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
}
func background(_ storage: NSTextStorage, at location: Int) -> NSColor? {
    storage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
}
func isBold(_ font: NSFont?) -> Bool {
    font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
}
func isItalic(_ font: NSFont?) -> Bool {
    font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
}
func isMono(_ font: NSFont?) -> Bool {
    font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
}

// MARK: - Headings

do {
    let s = styled("# Title\n\nbody\n")
    expect(font(s, at: 2)?.pointSize == EditorTheme.headingFont(level: 1, size: EditorTheme.defaultFontSize).pointSize, "h1 content is heading-sized")
    expect(isBold(font(s, at: 2)), "h1 content is bold")
    expect(color(s, at: 0) == EditorTheme.markerColor, "h1 # marker dimmed")
    expect(font(s, at: 9)?.pointSize == EditorTheme.defaultFontSize, "body after heading is body-sized")
    expect(color(s, at: 9) == NSColor.textColor, "body color is textColor")
}

do {
    let s = styled("### Third\n")
    expect(font(s, at: 5)?.pointSize == EditorTheme.headingFont(level: 3, size: EditorTheme.defaultFontSize).pointSize, "h3 sized")
    expect(color(s, at: 1) == EditorTheme.markerColor, "h3 marker dimmed")
}

// Not a heading without space
do {
    let s = styled("#nospace\n")
    expect(font(s, at: 1)?.pointSize == EditorTheme.defaultFontSize, "#nospace is not a heading")
}

// MARK: - Bold / italic / strikethrough

do {
    let text = "some **bold** words\n"
    let s = styled(text)
    let contentAt = (text as NSString).range(of: "bold").location
    expect(isBold(font(s, at: contentAt)), "**bold** content is bold")
    expect(color(s, at: contentAt - 1) == EditorTheme.markerColor, "bold opener dimmed")
    expect(color(s, at: contentAt + 4) == EditorTheme.markerColor, "bold closer dimmed")
    expect(!isBold(font(s, at: 0)), "text outside bold is regular")
}

do {
    let text = "an *italic* word and _under_ too\n"
    let s = styled(text)
    let starAt = (text as NSString).range(of: "italic").location
    let underAt = (text as NSString).range(of: "under").location
    expect(isItalic(font(s, at: starAt)), "*italic* content is italic")
    expect(isItalic(font(s, at: underAt)), "_under_ content is italic")
    expect(color(s, at: starAt - 1) == EditorTheme.markerColor, "italic marker dimmed")
}

do {
    let text = "not 2 * 3 * 4 math\n"
    let s = styled(text)
    let at = (text as NSString).range(of: "3").location
    expect(!isItalic(font(s, at: at)), "spaced asterisks are not italic")
}

// Triple markers: bold+italic content, all six markers dimmed, no strays.
do {
    let text = "a ***both*** b and ___under___ c\n"
    let s = styled(text)
    let starAt = (text as NSString).range(of: "both").location
    let underAt = (text as NSString).range(of: "under").location
    expect(isBold(font(s, at: starAt)) && isItalic(font(s, at: starAt)), "***both*** is bold italic")
    expect(isBold(font(s, at: underAt)) && isItalic(font(s, at: underAt)), "___under___ is bold italic")
    for offset in 1...3 {
        expect(color(s, at: starAt - offset) == EditorTheme.markerColor, "*** opener char \(offset) dimmed")
        expect(color(s, at: starAt + 3 + offset) == EditorTheme.markerColor, "*** closer char \(offset) dimmed")
    }
    let afterClose = (text as NSString).range(of: " b and").location
    expect(color(s, at: afterClose) == NSColor.textColor, "no stray marker after ***both***")
    expect(!isBold(font(s, at: afterClose)), "text after ***both*** is regular")
}

do {
    let text = "a ~~gone~~ word\n"
    let s = styled(text)
    let at = (text as NSString).range(of: "gone").location
    let strike = s.attribute(.strikethroughStyle, at: at, effectiveRange: nil) as? Int
    expect(strike == NSUnderlineStyle.single.rawValue, "~~strike~~ content struck")
}

// MARK: - Inline code

do {
    let text = "use `let x` here\n"
    let s = styled(text)
    let at = (text as NSString).range(of: "let x").location
    expect(isMono(font(s, at: at)), "inline code is monospaced")
    expect(background(s, at: at) != nil, "inline code has background")
    expect(color(s, at: at - 1) == EditorTheme.markerColor, "backtick dimmed")
    // bold inside code span must not style
    let s2 = styled("`a **b** c`\n")
    let bAt = 4
    expect(!isBold(font(s2, at: bAt)), "bold inside code span ignored")
}

// MARK: - Links

do {
    let text = "see [docs](https://example.com) now\n"
    let s = styled(text)
    let textAt = (text as NSString).range(of: "docs").location
    let urlAt = (text as NSString).range(of: "https").location
    expect(color(s, at: textAt) == EditorTheme.linkColor, "link text tinted")
    expect(color(s, at: urlAt) == EditorTheme.markerColor, "link url dimmed")
}

// MARK: - Blockquote, list, HR

do {
    let text = "> quoted words\n"
    let s = styled(text)
    expect(color(s, at: 0) == EditorTheme.markerColor, "> marker dimmed")
    expect(color(s, at: 3) == EditorTheme.quoteColor, "quote content quiet")
}

do {
    let text = "- item one\n2. item two\n"
    let s = styled(text)
    expect(font(s, at: 0) == EditorTheme.listMarkerFont(size: EditorTheme.defaultFontSize), "bullet emphasized")
    expect(font(s, at: 11) == EditorTheme.listMarkerFont(size: EditorTheme.defaultFontSize), "ordered marker emphasized")
    expect(font(s, at: 3)?.pointSize == EditorTheme.defaultFontSize, "list content is body")
}

do {
    let s = styled("above\n\n---\n\nbelow\n")
    let at = ("above\n\n" as NSString).length
    expect(color(s, at: at) == EditorTheme.markerColor, "--- horizontal rule dimmed")
}

// MARK: - Frontmatter

do {
    func detect(_ text: String) -> NSRange? { MarkdownFrontmatter.range(in: text as NSString) }
    expect(detect("---\na: b\n---\nbody\n") == NSRange(location: 0, length: 13), "frontmatter: block through closing newline")
    expect(detect("---\na: b\n...\n") == NSRange(location: 0, length: 13), "frontmatter: `...` terminator")
    expect(detect("---\n---\n") == NSRange(location: 0, length: 8), "frontmatter: empty block")
    expect(detect("---\na: b\n---") == NSRange(location: 0, length: 12), "frontmatter: closing fence at EOF")
    expect(detect("--- \t\na: b\n---  \n") != nil, "frontmatter: trailing whitespace on fences")
    expect(detect("---\r\na: b\r\n---\r\n") != nil, "frontmatter: CRLF fences")
    expect(detect("---\na: b\n") == nil, "frontmatter: no closing fence")
    expect(detect("---") == nil && detect("---\n") == nil, "frontmatter: lone opening fence")
    expect(detect("\n---\na: b\n---\n") == nil, "frontmatter: `---` not on line 1")
    expect(detect("----\na: b\n---\n") == nil, "frontmatter: four dashes do not open")
    expect(detect("---\na: b\n----\n") == nil, "frontmatter: four dashes do not close")
    expect(detect("---\na: b\n --- \n") == nil, "frontmatter: indented fence does not close")
    expect(detect("...\na: b\n...\n") == nil, "frontmatter: `...` does not open")
    expect(detect("---\n\n---\n") == NSRange(location: 0, length: 9), "frontmatter: blank-only block")
    expect(detect("---\nnote:\n---\n") != nil, "frontmatter: key with no value")
    expect(detect("---\n  indented: v\n---\n") == nil, "frontmatter: only an indented key does not count")
    expect(detect("---\n\"publish date\": 2026-09-24\n---\n# Post\n") != nil, "frontmatter: double-quoted key")
    expect(detect("---\n'k': v\n---\n") != nil, "frontmatter: single-quoted key")
    expect(detect("---\n\"Hi,\" she said: fine.\n---\n") == nil, "frontmatter: quoted prose is not a key")
}

// A document that opens with a `---` rule and has another rule further
// down is not frontmatter: no line between reads as a `key:`
// (heyeuca/Tilde#10 review).
let chapters = "---\n\n# Chapter One\n\nIt began quietly.\n\n---\n\n# Chapter Two\n\nThen it did not.\n"
let pause = "---\n\nShe paused.\n\n...\n\nAnd then she spoke.\n"

do {
    expect(MarkdownFrontmatter.range(in: chapters as NSString) == nil, "frontmatter: rule-delimited chapters are not frontmatter")
    expect(MarkdownFrontmatter.range(in: pause as NSString) == nil, "frontmatter: `...` after prose is not frontmatter")
    let s = styled(chapters)
    let ns = chapters as NSString
    expect(font(s, at: ns.range(of: "Chapter One").location)?.pointSize == EditorTheme.headingFont(level: 1, size: EditorTheme.defaultFontSize).pointSize, "frontmatter: chapter heading keeps heading style")
    expect(color(s, at: ns.range(of: "It began").location) == NSColor.textColor, "frontmatter: chapter body keeps body color")
    let p = styled(pause)
    expect(color(p, at: (pause as NSString).range(of: "She paused").location) == NSColor.textColor, "frontmatter: prose before `...` keeps body color")
}

do {
    // Adding the first `key:` line turns a rule-delimited section into
    // frontmatter; removing it turns it back.
    let storage = NSTextStorage(string: "---\n\n# One\n\n---\nbody\n")
    let styler = MarkdownStyler()
    storage.delegate = styler
    styler.restyleAll(storage)
    let headingSize = EditorTheme.headingFont(level: 1, size: EditorTheme.defaultFontSize).pointSize
    func oneAt() -> Int { (storage.string as NSString).range(of: "One").location }
    expect(font(storage, at: oneAt())?.pointSize == headingSize, "frontmatter: section without keys stays Markdown")
    storage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "k: v\n")
    expect(color(storage, at: oneAt()) == EditorTheme.quoteColor, "frontmatter: typing a key line makes the section metadata")
    storage.replaceCharacters(in: NSRange(location: 4, length: 5), with: "")
    expect(font(storage, at: oneAt())?.pointSize == headingSize, "frontmatter: deleting the key line restores Markdown")
}

do {
    let text = "---\ntitle: a_b_c\ntags:\n  - x\n---\n\nsome *it* here\n"
    let s = styled(text)
    let ns = text as NSString
    let closeAt = ns.range(of: "---\n\n").location
    expect(color(s, at: 0) == EditorTheme.markerColor, "frontmatter: opening fence dimmed")
    expect(color(s, at: closeAt) == EditorTheme.markerColor, "frontmatter: closing fence dimmed")
    expect(color(s, at: ns.range(of: "title").location) == EditorTheme.quoteColor, "frontmatter: metadata quiet")
    expect(!isItalic(font(s, at: ns.range(of: "b_c").location)), "frontmatter: no inline rules inside")
    expect(font(s, at: ns.range(of: "- x").location) != EditorTheme.listMarkerFont(size: EditorTheme.defaultFontSize), "frontmatter: `- x` is not a list")
    expect(isItalic(font(s, at: ns.range(of: "*it*").location + 1)), "frontmatter: Markdown resumes after the block")
}

do {
    let text = "---\nnote:\n```\n---\nbody\n"
    let s = styled(text)
    expect(!isMono(font(s, at: (text as NSString).range(of: "body").location)), "frontmatter: ``` inside the block opens no code fence")
}

do {
    // Closing the block around an open fence line re-pairs every fence below.
    let storage = NSTextStorage(string: "---\nk: v\n```\nbody\nmore\nlast\n")
    let styler = MarkdownStyler()
    storage.delegate = styler
    styler.restyleAll(storage)
    expect(isMono(font(storage, at: 13)), "frontmatter: unclosed block leaves ``` a fence")
    storage.replaceCharacters(in: NSRange(location: 13, length: 0), with: "---\n")
    let lastAt = (storage.string as NSString).range(of: "last").location
    expect(!isMono(font(storage, at: lastAt)), "frontmatter: closing the block restyles the fence's code below")
}

do {
    let s = styled("---\ntitle: x\n\nbody\n")
    expect(color(s, at: 0) == EditorTheme.markerColor, "frontmatter: unclosed `---` is still a horizontal rule")
    expect(color(s, at: 4) == NSColor.textColor, "frontmatter: unclosed block leaves lines as body")
}

do {
    let text = "intro\n---\nkey: v\n---\n"
    let s = styled(text)
    expect(color(s, at: (text as NSString).range(of: "key").location) == NSColor.textColor, "frontmatter: only recognized on line 1")
}

do {
    // Typing the closing fence turns the lines above into metadata;
    // deleting it turns them back.
    let storage = NSTextStorage(string: "---\ntitle: x\nbody\n")
    let styler = MarkdownStyler()
    storage.delegate = styler
    styler.restyleAll(storage)
    expect(color(storage, at: 4) == NSColor.textColor, "frontmatter: body before closing fence exists")
    storage.replaceCharacters(in: NSRange(location: 13, length: 0), with: "---\n")
    expect(color(storage, at: 4) == EditorTheme.quoteColor, "frontmatter: typing closing fence restyles the block")
    storage.replaceCharacters(in: NSRange(location: 13, length: 4), with: "")
    expect(color(storage, at: 4) == NSColor.textColor, "frontmatter: deleting closing fence restyles the block")
}

// MARK: - Fenced code blocks

do {
    let text = "before\n\n```swift\nlet a = 1\n**not bold**\n```\n\nafter **bold**\n"
    let s = styled(text)
    let ns = text as NSString
    let insideAt = ns.range(of: "let a").location
    let notBoldAt = ns.range(of: "not bold").location
    let afterBoldAt = ns.range(of: "bold**", options: .backwards).location
    expect(isMono(font(s, at: insideAt)), "fence interior monospaced")
    expect(s.attribute(EditorTheme.codeBlockMarker, at: insideAt, effectiveRange: nil) != nil, "fence interior marked as code block")
    expect(!isBold(font(s, at: notBoldAt)), "inline rules skipped inside fence")
    expect(color(s, at: ns.range(of: "```swift").location) == EditorTheme.markerColor, "fence marker line dimmed")
    expect(isBold(font(s, at: afterBoldAt)), "styling resumes after fence closes")
    expect(!isMono(font(s, at: ns.range(of: "before").location)), "text before fence untouched")
}

// Unclosed fence runs to EOF
do {
    let text = "start\n```\neverything now code\n"
    let s = styled(text)
    let at = (text as NSString).range(of: "everything").location
    expect(isMono(font(s, at: at)), "unclosed fence styles to EOF")
}

// MARK: - Empty lines (caret height)

do {
    // Empty lines carry their rhythm as paragraphSpacingBefore, never as
    // lineSpacing — lineSpacing is swallowed into an empty line's line box
    // and makes the caret 1.5× tall. Inside a fence too (it used to keep the
    // default style there), while still carrying the code-block marker so
    // the unified background stays continuous across blank lines.
    let text = "alpha\n\nbeta\n```\ncode1\n\ncode2\n```\n"
    let s = styled(text)
    let ns = text as NSString
    func style(_ at: Int) -> NSParagraphStyle? { s.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle }
    let outside = ns.range(of: "alpha\n").location + 6      // the empty line after alpha
    let inside = ns.range(of: "code1\n").location + 6       // the empty line after code1
    expect(style(outside)?.lineSpacing == 0 && (style(outside)?.paragraphSpacingBefore ?? 0) > 0, "empty line outside fence uses paragraphSpacingBefore")
    expect(style(inside)?.lineSpacing == 0 && (style(inside)?.paragraphSpacingBefore ?? 0) > 0, "empty line inside fence uses paragraphSpacingBefore")
    expect(style(inside)?.paragraphSpacingBefore == style(outside)?.paragraphSpacingBefore, "fence and body empty lines share one rhythm")
    expect(s.attribute(EditorTheme.codeBlockMarker, at: inside, effectiveRange: nil) != nil, "empty line inside fence keeps the code-block marker")
    expect(s.attribute(EditorTheme.codeBlockMarker, at: outside, effectiveRange: nil) == nil, "empty line outside fence has no code-block marker")
}

// MARK: - Caret on the final (virtual) line

do {
    // A document ending in a newline (or an empty one) lays out an extra
    // line for the last caret position inside the last paragraph's fragment.
    // It holds no character, so its geometry comes from the caret's typing
    // attributes. Measured live (#1, #7): the BODY paragraph style puts that
    // line on the 25 pt rhythm both after text and after a blank line; the
    // empty-line style landed it 8 pt off in opposite directions. The body
    // lineSpacing that then inflates the caret box is trimmed by the text
    // view (EditorTextView.caretHeight), not by the paragraph style.
    for mono in [false, true] {
        let typing = EditorTheme.typingAttributes(monospaced: mono, size: EditorTheme.defaultFontSize)
        let body = EditorTheme.bodyAttributes(monospaced: mono, size: EditorTheme.defaultFontSize)
        let font = EditorTheme.bodyFont(monospaced: mono, size: EditorTheme.defaultFontSize)
        expect((typing[.paragraphStyle] as? NSParagraphStyle) == (body[.paragraphStyle] as? NSParagraphStyle),
               "caret typing style is the body paragraph style (mono=\(mono))")
        expect((typing[.font] as? NSFont)?.pointSize == font.pointSize, "caret typing font is body-sized (mono=\(mono))")
        let caret = EditorTheme.caretHeight(monospaced: mono, size: EditorTheme.defaultFontSize)
        let textHeight = font.ascender - font.descender + font.leading
        expect(caret >= textHeight && caret < textHeight + 1, "caret height is the text height, not the line box (mono=\(mono))")
        expect(caret < textHeight + EditorTheme.lineSpacing(for: font), "caret height excludes lineSpacing (mono=\(mono))")
    }
}

// MARK: - Incremental restyle via delegate

do {
    let storage = NSTextStorage(string: "hello world\n")
    let styler = MarkdownStyler()
    storage.delegate = styler
    styler.restyleAll(storage)
    // Type "**" around a word — delegate should restyle the paragraph.
    storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "**")
    storage.replaceCharacters(in: NSRange(location: 13, length: 0), with: "**")
    let at = ("hello **wor" as NSString).length - 3
    expect(isBold(font(storage, at: at)), "delegate-driven restyle applies bold while typing")

    // Opening a fence flips the rest of the document.
    let storage2 = NSTextStorage(string: "alpha\nbeta\ngamma\n")
    let styler2 = MarkdownStyler()
    storage2.delegate = styler2
    styler2.restyleAll(storage2)
    storage2.replaceCharacters(in: NSRange(location: 6, length: 0), with: "```\n")
    let gammaAt = (storage2.string as NSString).range(of: "gamma").location
    expect(isMono(font(storage2, at: gammaAt)), "typing ``` restyles everything after it")
}

// MARK: - Fuzz: incremental fence cache must match a full scan

/// Applies 400 random edits through the delegate — some batched inside
/// one beginEditing/endEditing — and returns how many positions differ,
/// in any attribute, from a fresh full restyle.
func fuzzMismatches(start: String, pieces: [String]) -> Int {
    // Deterministic PRNG so failures are reproducible.
    var seed: UInt64 = 0x5eed
    func rand(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(bound))
    }

    let storage = NSTextStorage(string: start)
    let styler = MarkdownStyler()
    storage.delegate = styler
    styler.restyleAll(storage)

    var mismatches = 0
    for i in 0..<400 {
        let ns = storage.string as NSString
        let len = ns.length
        let kind = rand(4)
        if kind == 3, len >= 10 {
            // several edits delivered to the styler as one processEditing
            storage.beginEditing()
            for _ in 0..<(2 + rand(2)) {
                let length = storage.length
                let at = rand(length + 1)
                let removeLength = min(rand(4), length - at)
                storage.replaceCharacters(in: NSRange(location: at, length: removeLength), with: rand(2) == 0 ? pieces[rand(pieces.count)] : "")
            }
            storage.endEditing()
        } else if kind == 0 || len < 10 {
            // insert a random piece; often at the start, where line 1
            // decides whether a frontmatter block exists at all
            let at = rand(4) == 0 ? 0 : rand(len + 1)
            storage.replaceCharacters(in: NSRange(location: at, length: 0), with: pieces[rand(pieces.count)])
        } else if kind == 1 {
            // delete a random small range (can swallow whole fence lines)
            let at = rand(len)
            let deleteLength = min(1 + rand(8), len - at)
            storage.replaceCharacters(in: NSRange(location: at, length: deleteLength), with: "")
        } else {
            // replace a random range with a piece (delta can be zero)
            let at = rand(len)
            let replaceLength = min(rand(6), len - at)
            storage.replaceCharacters(in: NSRange(location: at, length: replaceLength), with: pieces[rand(pieces.count)])
        }

        // After each edit the styler's incremental cache must equal a fresh scan.
        let current = storage.string as NSString
        let fresh = MarkdownStyler.scanFenceLines(in: current, within: NSRange(location: 0, length: current.length))
        let freshStorage = NSTextStorage(string: storage.string)
        let freshStyler = MarkdownStyler()
        freshStyler.restyleAll(freshStorage)
        // Compare every attribute (paragraph style and the code-block
        // marker included) at every position.
        for at in 0..<current.length {
            let a = storage.attributes(at: at, effectiveRange: nil)
            let b = freshStorage.attributes(at: at, effectiveRange: nil)
            if !(a as NSDictionary).isEqual(to: b) {
                if mismatches == 0 {
                    print("mismatch at step \(i), offset \(at):\n  live:  \(a)\n  fresh: \(b)")
                    print("fresh fences: \(fresh)")
                }
                mismatches += 1
            }
        }
    }
    return mismatches
}

do {
    let pieces = ["hello ", "**b** ", "`c` ", "# h\n", "```\n", "code\n", "text\n", "> q\n", "- i\n", "\n", "~~s~~ ", "[l](u) "]
    let mismatches = fuzzMismatches(start: "start\n```\nfence\n```\nend\n", pieces: pieces)
    expect(mismatches == 0, "fuzz: 400 random edits — incremental styling matches full restyle (\(mismatches) mismatches)")
}

do {
    let pieces = ["---\n", "---", "...\n", "-", "\n", "key: v\n", "a_b_c ", "# h\n", "text\n", "```\n",
                  "---\n```\n", "key: v\n---\n", "\n---\n\n# h\n", "k:\n"]
    let mismatches = fuzzMismatches(start: "---\ntitle: x\n---\nbody\n---\nmore\n", pieces: pieces)
    expect(mismatches == 0, "fuzz: 400 frontmatter edits — incremental styling matches full restyle (\(mismatches) mismatches)")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
