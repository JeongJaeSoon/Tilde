#!/bin/bash
# Builds the direct-download (DMG) Tilde.app: the same target the App Store
# gets, plus Sparkle for in-app updates (#27).
#
#   scripts/build_direct.sh [xcodebuild build settings…]
#
# Sparkle is linked only here, through FRAMEWORK_SEARCH_PATHS, and the
# updater code compiles only `#if canImport(Sparkle)`. So the App Store
# archive, plain Xcode builds, and the swiftc test/smoke builds never
# contain it. Extra arguments go straight to xcodebuild: release.yml passes
# the Developer ID signing settings, CI passes CODE_SIGNING_ALLOWED=NO.
#
# Output: build/Build/Products/Release/Tilde.app with Sparkle.framework
# embedded but not yet signed — release.yml signs it (docs/RELEASING.md).

set -euo pipefail
cd "$(dirname "$0")/.."

FEED_URL="https://github.com/heyeuca/Tilde/releases/latest/download/appcast.xml"
# Public half of the EdDSA key that signs updates; Sparkle refuses any
# update not signed by its private half. Set once (docs/RELEASING.md).
PUBLIC_ED_KEY="GKmxrOYmZUyefCAJIA/30Pnt5kFDrZzxqKaSfmfKLYs="

SPARKLE_DIR="$(scripts/fetch_sparkle.sh)"
APP="build/Build/Products/Release/Tilde.app"

xcodebuild -project Tilde.xcodeproj -scheme Tilde -configuration Release \
    -derivedDataPath build \
    FRAMEWORK_SEARCH_PATHS="\$(inherited) \$(SRCROOT)/$SPARKLE_DIR" \
    OTHER_LDFLAGS="\$(inherited) -framework Sparkle" \
    ENABLE_PREVIEWS=NO \
    "$@" \
    build

# Xcode doesn't know about the framework, so embed it by hand. ditto keeps
# the framework's internal symlinks, which its code signature depends on.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Sparkle's MIT-style license asks for its notice to ship with every copy,
# and the framework bundle doesn't carry one.
cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

PLIST="$APP/Contents/Info.plist"
plist_set() {
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :$1 $3" "$PLIST"
}
plist_set SUFeedURL string "$FEED_URL"
# Sandboxed: install (and download, since Tilde has no network entitlement)
# through Sparkle's XPC services.
plist_set SUEnableInstallerLauncherService bool true
plist_set SUEnableDownloaderService bool true
# Manual checks only, and no "install automatically" checkbox.
plist_set SUEnableAutomaticChecks bool false
plist_set SUAllowsAutomaticUpdates bool false

if [[ -n "$PUBLIC_ED_KEY" ]]; then
    plist_set SUPublicEDKey string "$PUBLIC_ED_KEY"
else
    echo "warning: PUBLIC_ED_KEY is empty — this build can't install updates" >&2
fi

echo "$APP"
