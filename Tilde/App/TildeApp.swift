//
//  TildeApp.swift
//  Tilde
//

import SwiftUI

@main
struct TildeApp: App {
    #if canImport(Sparkle)
    private let updater = Updater()
    #endif

    init() {
        // Launching without a document creates a blank one (PRODUCT.md §10)
        // instead of the open panel document apps show by default.
        UserDefaults.standard.register(defaults: [
            "NSShowAppCentricOpenPanelInsteadOfUntitledFile": false,
        ])
        AppearanceSetting.applyAtLaunch()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { TextDocument() }) { configuration in
            EditorView(document: configuration.document, fileURL: configuration.fileURL)
        }
        // A compact unified title bar: the Reader toggle sits beside the file
        // name with no separate toolbar row.
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // Standard Find menu (⌘F / ⌘G / ⌥⌘F), routed to the text view's find bar.
            TextEditingCommands()
            ViewCommands()
            #if canImport(Sparkle)
            UpdateCommands(updater: updater)
            #endif
        }

        Settings {
            SettingsView()
        }
    }
}

/// View-menu items: wrap/line-number toggles and font size (⌘+ / ⌘- / ⌘0).
struct ViewCommands: Commands {
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.wordWrapKey) private var wordWrap = AppSettings.defaultWordWrap
    @AppStorage(AppSettings.lineNumbersKey) private var lineNumbers = AppSettings.defaultLineNumbers

    /// Bound to the frontmost Markdown document's Reader state; nil (and so
    /// disabled) for plain-text documents or when no document is focused.
    @FocusedValue(\.readerMode) private var readerMode

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            // Safari-style dynamic label and shortcut.
            Button((readerMode?.wrappedValue == true) ? "Hide Reader" : "Show Reader") {
                readerMode?.wrappedValue.toggle()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(readerMode == nil)

            Divider()

            Toggle("Word Wrap", isOn: $wordWrap)
            Toggle("Line Numbers", isOn: $lineNumbers)

            Divider()

            Button("Increase Font Size") {
                fontSize = AppSettings.increasedFontSize(fontSize)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                fontSize = max(fontSize - 1, AppSettings.fontSizeRange.lowerBound)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font Size") {
                fontSize = AppSettings.defaultFontSize
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()
        }
    }
}
