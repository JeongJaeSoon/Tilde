//
//  EditorView.swift
//  Tilde
//

import SwiftUI

/// Layout shell around the text editor; reads user settings and passes
/// them down as plain values.
struct EditorView: View {
    var document: TextDocument
    var fileURL: URL?

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.wordWrapKey) private var wordWrap = AppSettings.defaultWordWrap
    @AppStorage(AppSettings.lineNumbersKey) private var lineNumbers = AppSettings.defaultLineNumbers
    @AppStorage(AppSettings.markdownStylingKey) private var markdownStyling = AppSettings.defaultMarkdownStyling

    /// Reader mode is per-window and never persisted — a document always
    /// opens in the editor.
    @State private var isReaderMode = false

    /// Lets ReaderView ask the editor for its current reading position when
    /// it mounts, so the rendered view opens at the same place.
    @State private var scrollBridge = EditorScrollBridge()

    private var clampedFontSize: CGFloat { fontSize.clamped(to: AppSettings.fontSizeRange) }

    /// Markdown-ness follows the LIVE file URL: the current extension wins
    /// (Save As from `.md` to `.txt` switches modes immediately, and back);
    /// the open-time type only decides for extension-less files.
    private var isMarkdown: Bool {
        TextDocument.isMarkdown(openedAsMarkdown: document.isMarkdown, fileURL: fileURL)
    }

    var body: some View {
        ZStack {
            // The editor stays mounted underneath so caret, scroll, and IME
            // state survive the round trip into Reader and back.
            TextEditorView(
                document: document,
                isMarkdown: isMarkdown,
                fontSize: clampedFontSize,
                wordWrap: wordWrap,
                showLineNumbers: lineNumbers,
                markdownStyling: markdownStyling,
                fileURL: fileURL,
                scrollBridge: scrollBridge
            )
            .opacity(isReaderMode ? 0 : 1)

            if isReaderMode {
                ReaderView(
                    document: document,
                    fontSize: clampedFontSize,
                    fileURL: fileURL,
                    entryFraction: { scrollBridge.readFraction() },
                    onExit: { isReaderMode = false }
                )
            }
        }
        // On ANY Reader exit — Esc, the title-bar toggle, or ⌘⇧R — the
        // Reader's text view held first-responder status and is about to
        // unmount; hand focus back to the editor so typing resumes without
        // a click.
        .onChange(of: isReaderMode) { _, entering in
            if !entering { scrollBridge.focusEditor() }
        }
        // Save As from .md to .txt while Reader is open flips isMarkdown
        // off, which removes the toolbar toggle and disables ⌘⇧R — leave
        // Reader too, or the window would be stuck in a mode with no
        // visible exit. Routing through isReaderMode restores focus above.
        .onChange(of: isMarkdown) { _, isMarkdown in
            if !isMarkdown { isReaderMode = false }
        }
        .ignoresSafeArea()
        // Applied after ignoresSafeArea so the bar sits below the title bar
        // (inside the window's safe area) while the text stays full-bleed.
        .safeAreaInset(edge: .top, spacing: 0) {
            // A document whose bytes couldn't be decoded exactly opens
            // read-only (saving would corrupt the original); this quiet bar
            // is the explanation for the unresponsive keyboard.
            if document.isLossy {
                LossyEncodingNotice()
            }
        }
        // ⌘= catcher: .keyboardShortcut("+") only fires on the shifted key
        // (⌘⇧=), while Safari/TextEdit/Terminal all accept plain ⌘= for
        // zoom-in. An invisible button supplies the second key equivalent.
        .background {
            Button {
                fontSize = AppSettings.increasedFontSize(fontSize)
            } label: {
                Text(verbatim: "")   // not a localizable string
            }
            .keyboardShortcut("=", modifiers: .command)
            .buttonStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        // No "Reader" subtitle: the title bar toggle (and the rendered
        // content itself) already convey the mode, and the title area shows
        // only the file name (PRODUCT.md §17).
        .publishReaderToggle($isReaderMode, enabled: isMarkdown)
        .focusedSceneValue(\.markdownFormatting, isMarkdown && !isReaderMode && !document.isLossy)
        .toolbar {
            // A single quiet toggle in the title bar — usable only for
            // Markdown documents, but the toolbar ITEM exists for every
            // window: without any toolbar AppKit gives the window a
            // shorter title bar with a permanently visible proxy icon, so
            // .md and .txt windows looked subtly different (and Save As
            // between the two made the title bar jump). An invisible,
            // disabled placeholder keeps plain-text windows chrome-free
            // while every window shares one title-bar treatment.
            ToolbarItem(placement: .primaryAction) {
                if isMarkdown {
                    Button {
                        isReaderMode.toggle()
                    } label: {
                        Label {
                            Text("Reader")
                        } icon: {
                            Image(systemName: "book")
                                .symbolVariant(isReaderMode ? .fill : .none)
                                // Keep both symbol variants in the same toolbar
                                // slot so their intrinsic bounds cannot move
                                // the Reader control's optical center.
                                .frame(width: 18, height: 18)
                        }
                    }
                    .help(isReaderMode ? "Hide Reader (⌘⇧R)" : "Reader (⌘⇧R)")
                } else {
                    // A flexible space, not a control: a disabled button
                    // (or any fixed-size view) still gets a glass item
                    // capsule, while a spacer keeps the toolbar alive
                    // without drawing anything.
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Lossy-encoding notice

/// One quiet line shown above a document whose bytes couldn't be decoded
/// exactly. It explains the read-only state; the hard save block lives in
/// `TextDocument.fileWrapper`.
private struct LossyEncodingNotice: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("Unsupported text encoding — opened read-only to protect the file.")
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Reader command wiring

/// Focused binding the View menu's Reader command drives. Present only for
/// the frontmost Markdown document window; nil elsewhere disables ⌘⇧R.
struct ReaderModeFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var readerMode: Binding<Bool>? {
        get { self[ReaderModeFocusedValueKey.self] }
        set { self[ReaderModeFocusedValueKey.self] = newValue }
    }
}

private extension View {
    /// Publishes the Reader toggle only for Markdown documents, so the
    /// command is disabled for plain text. Publishing nil (instead of an
    /// `if` branch) keeps view identity stable when markdown-ness changes
    /// at Save As time.
    func publishReaderToggle(_ binding: Binding<Bool>, enabled: Bool) -> some View {
        focusedSceneValue(\.readerMode, enabled ? binding : nil)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> CGFloat {
        CGFloat(Swift.min(Swift.max(self, range.lowerBound), range.upperBound))
    }
}
