//
//  MarkdownLink.swift
//  Tilde
//

import AppKit

/// Link rules shared by Reader's clickable links and the editor's ⌘-click,
/// so a link goes to the same place whichever view it is followed from.
nonisolated enum MarkdownLink {
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

    /// The slug a `#fragment` link asks for: percent-decoded, then slugified
    /// the same way heading text is.
    static func anchorSlug(forFragment fragment: String) -> String {
        anchorSlug(for: fragment.removingPercentEncoding ?? fragment)
    }

    /// `base`, or the first of `base-1`, `base-2`… not yet in `used` — the
    /// way GitHub disambiguates duplicate headings. A set (not a counter)
    /// so a suffixed slug can never collide with a heading that slugs to
    /// the same text naturally ("Foo", "Foo", "Foo 1").
    static func uniqueAnchor(_ base: String, used: inout Set<String>) -> String {
        var slug = base
        var suffix = 1
        while used.contains(slug) {
            slug = "\(base)-\(suffix)"
            suffix += 1
        }
        used.insert(slug)
        return slug
    }

    /// Where a click on this link should actually go. Markdown hands
    /// relative targets through nearly verbatim, and nothing can open
    /// those — so `README.ko.md` silently did nothing. Scheme'd URLs pass
    /// through, relative paths resolve against the document's directory
    /// into file URLs, and fragment-only links stay as-is for an
    /// in-document jump.
    static func resolved(_ url: URL, against baseURL: URL?) -> URL {
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

    /// What following a resolved link does.
    enum Destination: Equatable {
        /// Jump to the heading with this fragment in the same document.
        case anchor(String)
        /// Open this local file (fragment stripped) as its own document.
        case file(URL)
        /// Hand to the system default (browser, Mail, …).
        case external(URL)
    }

    /// Where a resolved link leads; nil for a relative link that couldn't
    /// resolve (an untitled document has no directory to anchor it).
    static func destination(of url: URL) -> Destination? {
        if url.scheme == nil, url.relativePath.isEmpty, let fragment = url.fragment {
            return .anchor(fragment)
        }
        if url.isFileURL { return .file(URL(fileURLWithPath: url.path)) }
        if url.scheme != nil { return .external(url) }
        return nil
    }

    /// The URL in an editor link's raw `(…)` target: an optional `<…>`
    /// wrapper and a trailing `"title"` are dropped, and characters a URL
    /// can't hold (a space in `<my file.md>`) are percent-encoded.
    static func url(fromTarget raw: String) -> URL? {
        var target = raw.trimmingCharacters(in: .whitespaces)
        if target.hasPrefix("<"), let close = target.firstIndex(of: ">") {
            target = String(target[target.index(after: target.startIndex)..<close])
        } else if let space = target.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            target = String(target[..<space])
        }
        guard !target.isEmpty else { return nil }
        if let url = URL(string: target) { return url }
        return target.addingPercentEncoding(withAllowedCharacters: urlAllowed).flatMap(URL.init(string:))
    }

    private static let urlAllowed = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#"))

    /// Follows a resolved link: an anchor goes to `scrollToAnchor`, a local
    /// file opens as its own document window, and a scheme'd URL goes to
    /// the system default. Under the sandbox a file opens only when the app
    /// can already read it — on failure the user just hears the beep.
    /// Returns false, doing nothing, when the link leads nowhere.
    @MainActor
    static func open(_ url: URL, scrollToAnchor: (String) -> Void) -> Bool {
        switch destination(of: url) {
        case .anchor(let fragment):
            scrollToAnchor(fragment)
        case .file(let file):
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
                if error != nil { NSSound.beep() }
            }
        case .external(let external):
            NSWorkspace.shared.open(external)
        case nil:
            return false
        }
        return true
    }
}
