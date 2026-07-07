#!/usr/bin/env bash
# AMA-2281 / absorbs AMA-2270 — Generate "What to Test" from merged PR titles since
# the previous testflight/build* tag, then set via App Store Connect betaBuildLocalizations.
set -euo pipefail

: "${BUILD_NUMBER:?BUILD_NUMBER required}"
: "${ASC_KEY_ID:?ASC_KEY_ID required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID required}"
: "${ASC_PRIVATE_KEY:?ASC_PRIVATE_KEY required}"

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.myamaka.AmakaFlowCompanion}"
MAX_NOTES_CHARS="${MAX_NOTES_CHARS:-4000}"
LOCALE="${TESTFLIGHT_NOTES_LOCALE:-en-US}"

generate_notes() {
  local prev_tag prev_sha notes
  prev_tag="$(git tag -l 'testflight/build*' --sort=-version:refname | head -1 || true)"
  if [ -n "$prev_tag" ]; then
    prev_sha="$(git rev-parse "${prev_tag}^{commit}")"
    echo "Generating notes since tag $prev_tag ($prev_sha)…" >&2
    notes="$(git log "${prev_sha}..HEAD" --merges --pretty=format:'- %s' 2>/dev/null || true)"
  else
    echo "No prior testflight/build* tag — using last 30 merge commits." >&2
    notes="$(git log --merges --pretty=format:'- %s' -30 2>/dev/null || true)"
  fi
  if [ -z "$notes" ]; then
    notes="- CI build ${BUILD_NUMBER} ($(git rev-parse --short HEAD))"
  fi
  # Strip [AMA-XXXX] ticket prefixes where present.
  notes="$(printf '%s\n' "$notes" | sed -E 's/\[AMA-[0-9]+\][[:space:]]*//g')"
  if [ "${#notes}" -gt "$MAX_NOTES_CHARS" ]; then
    notes="${notes:0:$((MAX_NOTES_CHARS - 20))}

… (truncated)"
  fi
  printf '%s' "$notes"
}

NOTES="$(generate_notes)"
echo "=== What to Test preview (${#NOTES} chars) ==="
printf '%s\n' "$NOTES"
echo "=============================================="

# macOS runners use PEP 668 externally-managed Python — install into a temp venv.
NOTES_VENV="$(mktemp -d)/notes-venv"
python3 -m venv "$NOTES_VENV"
"$NOTES_VENV/bin/pip" install --quiet PyJWT cryptography

export BUILD_NUMBER APP_BUNDLE_ID LOCALE
export ASC_KEY_ID ASC_ISSUER_ID
NOTES_FILE="$(mktemp)"
printf '%s' "$NOTES" > "$NOTES_FILE"
export NOTES_FILE

"$NOTES_VENV/bin/python" <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
PRIVATE_KEY = os.environ["ASC_PRIVATE_KEY"]
BUILD_NUMBER = os.environ["BUILD_NUMBER"]
BUNDLE_ID = os.environ["APP_BUNDLE_ID"]
LOCALE = os.environ["LOCALE"]
NOTES_PATH = os.environ["NOTES_FILE"]

with open(NOTES_PATH, encoding="utf-8") as fh:
    whats_new = fh.read().strip()

if not whats_new:
    print("::error::Generated What-to-Test notes are empty.", file=sys.stderr)
    sys.exit(1)


def make_token() -> str:
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    headers = {"kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, PRIVATE_KEY, algorithm="ES256", headers=headers)


def api(method: str, path: str, body: dict | None = None) -> dict:
    url = f"https://api.appstoreconnect.apple.com/v1{path}"
    data = None
    headers = {
        "Authorization": f"Bearer {make_token()}",
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"::error::ASC API {method} {path} failed ({exc.code}): {detail}", file=sys.stderr)
        sys.exit(1)


def get_app_id() -> str:
    q = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID})
    resp = api("GET", f"/apps?{q}")
    data = resp.get("data") or []
    if not data:
        print(f"::error::No ASC app found for bundleId={BUNDLE_ID}", file=sys.stderr)
        sys.exit(1)
    return data[0]["id"]


def find_build_id(app_id: str) -> str:
    q = urllib.parse.urlencode(
        {"filter[app]": app_id, "filter[version]": BUILD_NUMBER, "limit": "1"}
    )
    for attempt in range(1, 31):
        resp = api("GET", f"/builds?{q}")
        data = resp.get("data") or []
        if data:
            build_id = data[0]["id"]
            print(f"Found ASC build id={build_id} (attempt {attempt})")
            return build_id
        print(f"Build {BUILD_NUMBER} not visible yet — retry {attempt}/30 in 10s…")
        time.sleep(10)
    print(
        f"::error::Build {BUILD_NUMBER} not found in App Store Connect after upload.",
        file=sys.stderr,
    )
    sys.exit(1)


def get_localization(build_id: str) -> dict | None:
    resp = api("GET", f"/builds/{build_id}/betaBuildLocalizations")
    data = resp.get("data") or []
    for loc in data:
        if loc.get("attributes", {}).get("locale") == LOCALE:
            return loc
    return data[0] if data else None


def set_whats_new(build_id: str) -> None:
    loc = get_localization(build_id)
    if loc:
        loc_id = loc["id"]
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "id": loc_id,
                "attributes": {"whatsNew": whats_new},
            }
        }
        api("PATCH", f"/betaBuildLocalizations/{loc_id}", body)
        print(f"✅ Updated betaBuildLocalization {loc_id} ({LOCALE})")
    else:
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": LOCALE, "whatsNew": whats_new},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        }
        resp = api("POST", "/betaBuildLocalizations", body)
        loc_id = resp.get("data", {}).get("id", "?")
        print(f"✅ Created betaBuildLocalization {loc_id} ({LOCALE})")


app_id = get_app_id()
print(f"ASC app id={app_id} bundleId={BUNDLE_ID}")
build_id = find_build_id(app_id)
set_whats_new(build_id)
print("::notice title=What to Test set::Notes applied via betaBuildLocalizations API.")
PY

rm -f "$NOTES_FILE"
rm -rf "$(dirname "$NOTES_VENV")"
echo "✅ What to Test notes set for build ${BUILD_NUMBER}."
