#!/bin/bash
# Compiles and runs Tilde's test suites as plain executables.
#
# No XCTest, no Xcode required — only the Command Line Tools — so the same
# suites run on a dev machine without Xcode and on CI. Each suite is a
# main.swift compiled together with the production sources it exercises.

set -u
cd "$(dirname "$0")/.."

TARGET="arm64-apple-macos14.0"
if [[ "$(uname -m)" == "x86_64" ]]; then TARGET="x86_64-apple-macos14.0"; fi
SDK="$(xcrun --show-sdk-path)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

build_and_run() {
    local name="$1"; shift
    echo "== $name"
    if ! xcrun swiftc -O -target "$TARGET" -sdk "$SDK" \
        -o "$BUILD_DIR/$name" "$@" 2>&1 | grep -v -i "warning"; then
        : # swiftc noise filtered; failure detected via missing binary below
    fi
    if [[ ! -x "$BUILD_DIR/$name" ]]; then
        echo "FAIL  $name did not compile"
        return 1
    fi
    "$BUILD_DIR/$name"
}

status=0

build_and_run DocumentTests \
    Tilde/Document/FileEncoding.swift \
    Tilde/Document/LineEnding.swift \
    Tilde/Document/TextDocument.swift \
    Tests/DocumentTests/main.swift || status=1

build_and_run LineIndexTests \
    Tilde/Editor/LineIndex.swift \
    Tests/LineIndexTests/main.swift || status=1

build_and_run StylerTests \
    Tilde/Editor/EditorTheme.swift \
    Tilde/Editor/CodeSyntaxStyler.swift \
    Tilde/Editor/MarkdownFrontmatter.swift \
    Tilde/Editor/MarkdownStyler.swift \
    Tests/StylerTests/main.swift || status=1

build_and_run CodeSyntaxTests \
    Tilde/Editor/EditorTheme.swift \
    Tilde/Editor/CodeSyntaxStyler.swift \
    Tests/CodeSyntaxTests/main.swift || status=1

build_and_run LexerTests \
    Tilde/Editor/EditorTheme.swift \
    Tilde/Reader/CodeHighlighter.swift \
    Tests/LexerTests/main.swift || status=1

build_and_run LocalizationTests \
    Tests/LocalizationTests/main.swift || status=1

build_and_run RendererTests \
    Tilde/Editor/EditorTheme.swift \
    Tilde/Editor/MarkdownFrontmatter.swift \
    Tilde/Reader/CodeHighlighter.swift \
    Tilde/Reader/MarkdownRenderer.swift \
    Tests/RendererTests/main.swift || status=1

if [[ $status -eq 0 ]]; then
    echo "== all suites passed"
else
    echo "== FAILURES above"
fi
exit $status
