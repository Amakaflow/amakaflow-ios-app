#!/usr/bin/env bash
set -euo pipefail

: "${XCODE_VERSION:?XCODE_VERSION must be set, for example 26.2}"

XCODE_PATH="/Applications/Xcode_${XCODE_VERSION}.app"

if [ ! -d "$XCODE_PATH" ]; then
  echo "::error::Pinned Xcode not found at $XCODE_PATH"
  echo "Available Xcode installations:"
  ls -d /Applications/Xcode*.app 2>/dev/null || true
  exit 1
fi

echo "Using Xcode: $XCODE_PATH"
sudo xcode-select -s "$XCODE_PATH"
xcodebuild -version

XCODE_VER=$(xcodebuild -version | head -1 | tr ' ' '-')
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$XCODE_VER" >> "$GITHUB_OUTPUT"
fi
