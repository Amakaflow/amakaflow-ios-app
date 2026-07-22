#!/usr/bin/env bash
# AMA-2281 — Push testflight/buildNNN tag at github.sha after a successful upload.
# Tag is the "last built SHA" anchor for What-to-Test diffing on the next release.
set -euo pipefail

BUILD_NUMBER="${1:?BUILD_NUMBER required}"
: "${GITHUB_SHA:?GITHUB_SHA required}"

TAG="testflight/build${BUILD_NUMBER}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  EXISTING="$(git rev-parse "$TAG^{commit}")"
  if [ "$EXISTING" = "$GITHUB_SHA" ]; then
    echo "Tag $TAG already points at $GITHUB_SHA — nothing to push."
    exit 0
  fi
  echo "::error::Tag $TAG already exists at $EXISTING but this run is $GITHUB_SHA — refusing to overwrite."
  exit 1
fi

git tag "$TAG" "$GITHUB_SHA"

# Checkout uses persist-credentials: false (secrets hygiene). Re-auth with
# the job's GITHUB_TOKEN so tag push works under contents: write.
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi

git push origin "refs/tags/${TAG}"
echo "✅ Pushed tag $TAG → $GITHUB_SHA"
