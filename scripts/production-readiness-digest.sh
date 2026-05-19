#!/usr/bin/env bash
#
# AMA-1853 / Production-Ready v1 — Daily Telegram digest.
#
# Runs via launchd at 05:00 US Central daily (see
# ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist).
# Independent of any Claude Code session — pure shell + curl.
#
# What it posts:
#   1. PRs merged in the last 24h (across amakaflow-ios-app + amakaflow-backend)
#   2. PRs currently open + mergeable (the "ready to tap" list)
#   3. Linear tickets in Production-Ready v1 project (gap status snapshot)
#   4. Manual-action items waiting on David
#
# Environment expected:
#   TELEGRAM_BOT_TOKEN  — from ~/.claude/channels/telegram/.env
#   TELEGRAM_CHAT_ID    — defaults to David's chat (7888191549)
#   LINEAR_API_KEY      — from ~/.claude/projects/-Users-davidmini/secrets/keys.env
#   GH_TOKEN or `gh` CLI auth
#
# Verify by:
#   - Run `scripts/production-readiness-digest.sh` from terminal → message arrives on Telegram
#   - Check `/Volumes/SSD1/openclaw/logs/production-digest.log` for last run timestamp + payload

set -euo pipefail

# ---------- load secrets ----------

KEYS="$HOME/.claude/projects/-Users-davidmini/secrets/keys.env"
TG_ENV="$HOME/.claude/channels/telegram/.env"

if [ -f "$TG_ENV" ]; then
  # shellcheck source=/dev/null
  . "$TG_ENV"
fi

if [ -f "$KEYS" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$KEYS"
  set +a
fi

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set — check ~/.claude/channels/telegram/.env}"
: "${LINEAR_API_KEY:?LINEAR_API_KEY not set — check secrets/keys.env}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-7888191549}"

LOG="/Volumes/SSD1/openclaw/logs/production-digest.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "=== digest run start ==="

# ---------- helpers ----------

# Linear GraphQL query
linear_query() {
  local query="$1"
  curl -sS -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":$(jq -Rs . <<<"$query")}"
}

# ---------- data fetch ----------

since=$(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')

# Merged PRs in last 24h
merged_ios=$(gh pr list -R Amakaflow/amakaflow-ios-app --state merged --limit 30 --json number,title,mergedAt --jq "[.[] | select(.mergedAt > \"$since\")]")
merged_be=$(gh pr list -R Amakaflow/amakaflow-backend --state merged --limit 30 --json number,title,mergedAt --jq "[.[] | select(.mergedAt > \"$since\")]")

# Open PRs (any state, any mergeable status)
open_ios=$(gh pr list -R Amakaflow/amakaflow-ios-app --state open --json number,title,mergeStateStatus,isDraft)
open_be=$(gh pr list -R Amakaflow/amakaflow-backend --state open --json number,title,mergeStateStatus,isDraft)

# Linear: Production-Ready v1 project tickets (open)
linear_pr_v1=$(linear_query 'query {
  projects(filter: { name: { eq: "Production-Ready v1" } }) {
    nodes {
      issues(filter: { state: { type: { neq: "completed" } } }) {
        nodes { identifier title state { name } priorityLabel }
      }
    }
  }
}')

# Linear: AMA tickets completed in last 24h
linear_done=$(linear_query "query {
  issues(
    filter: {
      team: { key: { eq: \"AMA\" } }
      completedAt: { gte: \"$since\" }
    }
    first: 30
  ) {
    nodes { identifier title }
  }
}")

# ---------- compose message ----------

# Section: merged PRs
merged_section=""
n_merged=$(jq -s '[.[][]] | length' <<<"$merged_ios"$'\n'"$merged_be")
if [ "$n_merged" -gt 0 ]; then
  merged_section="✅ *Merged last 24h ($n_merged)*"$'\n'
  while IFS= read -r line; do
    [ -n "$line" ] && merged_section+="  • $line"$'\n'
  done < <(jq -r '.[] | "ios#\(.number) — \(.title)"' <<<"$merged_ios")
  while IFS= read -r line; do
    [ -n "$line" ] && merged_section+="  • $line"$'\n'
  done < <(jq -r '.[] | "be#\(.number) — \(.title)"' <<<"$merged_be")
fi

# Section: open PRs by state
open_clean_section=""
open_other_section=""
all_open=$(jq -s '
  (.[0] | map(. + {repo: "ios"})) + (.[1] | map(. + {repo: "be"}))
' <<<"$open_ios"$'\n'"$open_be")
n_clean=$(jq '[.[] | select(.mergeStateStatus == "CLEAN" and (.isDraft | not))] | length' <<<"$all_open")
if [ "$n_clean" -gt 0 ]; then
  open_clean_section="🟢 *Ready to tap-merge ($n_clean)*"$'\n'
  while IFS= read -r line; do
    [ -n "$line" ] && open_clean_section+="  • $line"$'\n'
  done < <(jq -r '.[] | select(.mergeStateStatus == "CLEAN" and (.isDraft | not)) | "\(.repo)#\(.number) — \(.title)"' <<<"$all_open")
fi

n_other=$(jq '[.[] | select(.mergeStateStatus != "CLEAN" and (.isDraft | not))] | length' <<<"$all_open")
if [ "$n_other" -gt 0 ]; then
  open_other_section="🟡 *Open, needs attention ($n_other)*"$'\n'
  while IFS= read -r line; do
    [ -n "$line" ] && open_other_section+="  • $line"$'\n'
  done < <(jq -r '.[] | select(.mergeStateStatus != "CLEAN" and (.isDraft | not)) | "\(.repo)#\(.number) [\(.mergeStateStatus)] — \(.title)"' <<<"$all_open")
fi

# Section: Production-Ready v1 gap snapshot
pr_v1_nodes=$(jq -r '.data.projects.nodes[0].issues.nodes // [] | sort_by(.identifier)' <<<"$linear_pr_v1")
n_pr_v1=$(jq 'length' <<<"$pr_v1_nodes")
pr_v1_section="🚀 *Production-Ready v1 ($n_pr_v1 open)*"$'\n'
if [ "$n_pr_v1" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && pr_v1_section+="  • $line"$'\n'
  done < <(jq -r '.[] | "\(.identifier) [\(.state.name)] [\(.priorityLabel // "—")] — \(.title)"' <<<"$pr_v1_nodes")
else
  pr_v1_section+="  • All gaps closed 🎉"$'\n'
fi

# Section: Linear-completed last 24h
done_section=""
n_linear_done=$(jq '.data.issues.nodes | length' <<<"$linear_done")
if [ "$n_linear_done" -gt 0 ]; then
  done_section="📋 *Linear closed last 24h ($n_linear_done)*"$'\n'
  while IFS= read -r line; do
    [ -n "$line" ] && done_section+="  • $line"$'\n'
  done < <(jq -r '.data.issues.nodes[] | "\(.identifier) — \(.title)"' <<<"$linear_done")
fi

# Header
header="🦞 *AmakaFlow Daily Digest — $(date '+%a %b %-d')*"$'\n\n'

# Assemble (skip empty sections)
message="$header"
for section in "$merged_section" "$open_clean_section" "$open_other_section" "$pr_v1_section" "$done_section"; do
  if [ -n "$section" ]; then
    message+="$section"$'\n'
  fi
done

# Footer
message+=$'\n''_Dashboard:_ [Production-Ready v1](https://linear.app/amakaflow/project/production-ready-v1-2ea0beaf4e0b)'

log "composed message ($(wc -c <<<"$message" | tr -d ' ') chars)"
log "preview: $(head -c 200 <<<"$message")"

# ---------- send ----------

response=$(curl -sS -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -nR --arg chat "$TELEGRAM_CHAT_ID" --arg text "$message" '{chat_id: $chat | tonumber, text: $text, parse_mode: "Markdown", disable_web_page_preview: true}')")

if echo "$response" | jq -e '.ok == true' > /dev/null; then
  log "sent OK message_id=$(echo "$response" | jq -r '.result.message_id')"
  exit 0
else
  log "FAILED: $response"
  exit 1
fi
