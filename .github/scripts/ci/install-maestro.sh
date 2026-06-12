#!/usr/bin/env bash
set -euo pipefail

: "${MAESTRO_VERSION:?MAESTRO_VERSION must be set, for example 2.6.1}"

export MAESTRO_VERSION
export PATH="$HOME/.maestro/bin:$PATH"

if command -v maestro >/dev/null 2>&1 && maestro --version | grep -q "$MAESTRO_VERSION"; then
  echo "Maestro $MAESTRO_VERSION restored from cache."
else
  echo "Installing Maestro $MAESTRO_VERSION"
  curl -fsSL "https://get.maestro.mobile.dev" | bash
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"
fi
