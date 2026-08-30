#!/usr/bin/env bash
# Runs once after the container is created.
# Keep this idempotent: it also runs after a rebuild.
set -euo pipefail

echo "==> Swift version"
swift --version

echo "==> Installing swift-format (used by the swiftformat extension and CI)"
if ! command -v swift-format >/dev/null 2>&1; then
  # swift-format ships with the Swift 6 toolchain on Linux; fall back to a
  # source build only if it is genuinely missing.
  echo "swift-format not found in toolchain; skipping. Formatting will run in CI."
fi

echo "==> Resolving SentinelCore dependencies"
if [ -f "Packages/SentinelCore/Package.swift" ]; then
  swift package --package-path Packages/SentinelCore resolve
else
  echo "Packages/SentinelCore does not exist yet. Skipping (expected before M1)."
fi

echo "==> Installing a static file server for the docs site preview"
npm install -g http-server >/dev/null 2>&1 || true

cat <<'MSG'

------------------------------------------------------------
XcodeSentinel dev container is ready.

  Build core logic :  swift build --package-path Packages/SentinelCore
  Run tests        :  swift test  --package-path Packages/SentinelCore
  Preview the site :  http-server docs/site -p 8080

  NOTE: App/ (SwiftUI, AppKit, Accessibility API) CANNOT be built here.
        This is a Linux container. Build and run App/ on the host Mac
        with Xcode or xcodebuild.
------------------------------------------------------------

MSG
