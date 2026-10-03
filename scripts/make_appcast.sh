#!/bin/bash
# Writes the Sparkle appcast (update feed) for one release (#27).
#
#   SPARKLE_ED_PRIVATE_KEY=… scripts/make_appcast.sh <Tilde.app> <Tilde-vX.Y.Z.dmg> <vX.Y.Z> <appcast.xml>
#
# The feed lists only this release. Tilde reads it from
# releases/latest/download/appcast.xml, which always resolves to the newest
# release, so older entries would never be read.
#
# Release notes come from docs/releases/<tag>-draft.md: everything between
# the title and "## Install" (the install steps make no sense in an update
# dialog). Sparkle 2.9+ renders them as Markdown.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: make_appcast.sh <Tilde.app> <dmg> <tag> <appcast.xml>}"
DMG="${2:?usage: make_appcast.sh <Tilde.app> <dmg> <tag> <appcast.xml>}"
TAG="${3:?usage: make_appcast.sh <Tilde.app> <dmg> <tag> <appcast.xml>}"
OUT="${4:?usage: make_appcast.sh <Tilde.app> <dmg> <tag> <appcast.xml>}"
: "${SPARKLE_ED_PRIVATE_KEY:?set SPARKLE_ED_PRIVATE_KEY — see docs/RELEASING.md}"

SPARKLE_DIR="$(scripts/fetch_sparkle.sh)"

PLIST="$APP/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
BUILD="$(read_plist CFBundleVersion)"
VERSION="$(read_plist CFBundleShortVersionString)"
MIN_OS="$(read_plist LSMinimumSystemVersion 2>/dev/null || echo 14.0)"

# A feed signed with any other key would make every install refuse the
# update, so stop here instead of publishing it.
APP_KEY="$(read_plist SUPublicEDKey 2>/dev/null || true)"
SECRET_KEY="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | swift scripts/sparkle_public_key.swift)"
if [[ "$APP_KEY" != "$SECRET_KEY" ]]; then
    echo "error: SPARKLE_ED_PRIVATE_KEY doesn't match the app's SUPublicEDKey" >&2
    exit 1
fi

SIGNATURE="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" \
    | "$SPARKLE_DIR/bin/sign_update" --ed-key-file - -p "$DMG")"
LENGTH="$(stat -f %z "$DMG")"
DMG_URL="https://github.com/heyeuca/Tilde/releases/download/$TAG/$(basename "$DMG")"
RELEASE_URL="https://github.com/heyeuca/Tilde/releases/tag/$TAG"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

DESCRIPTION=""
NOTES_FILE="docs/releases/$TAG-draft.md"
if [[ -f "$NOTES_FILE" ]]; then
    NOTES="$(awk 'NR == 1 && /^# / { next } /^## Install/ { exit } { print }' "$NOTES_FILE")"
    # A literal "]]>" would end the CDATA section early.
    NOTES="${NOTES//']]>'/']]]]><![CDATA[>'}"
    DESCRIPTION="      <description sparkle:format=\"markdown\"><![CDATA[$NOTES]]></description>"
fi

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tilde</title>
    <item>
      <title>Tilde $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$RELEASE_URL</sparkle:fullReleaseNotesLink>
$DESCRIPTION
      <enclosure url="$DMG_URL" length="$LENGTH" type="application/octet-stream"
                 sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML

xmllint --noout "$OUT"
echo "wrote $OUT (Tilde $VERSION, build $BUILD)"
