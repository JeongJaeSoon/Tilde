//
//  Updater.swift
//  Tilde
//

// In-app updates, for the direct-download (DMG) build only (#27). Sparkle
// is linked by scripts/build_direct.sh and nowhere else, so the App Store
// build, plain Xcode builds, and the swiftc test/smoke builds compile none
// of this file.
#if canImport(Sparkle)
import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's standard updater and its dialogs. Checks run only when the
/// user picks Check for Updates…: build_direct.sh turns automatic checks off
/// (PRODUCT.md §29 — no update polling).
final class Updater: ObservableObject {
    /// False while a check or an update is already in progress.
    @Published private(set) var canCheckForUpdates = false

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Tilde menu → Check for Updates…, right below About Tilde.
struct UpdateCommands: Commands {
    let updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updater: updater)
        }
    }
}

/// A view rather than a bare Button so it can observe `canCheckForUpdates`.
private struct CheckForUpdatesButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
#endif
