# launchd plists

Source-of-truth copies of the launchd LaunchAgents this repo expects on the developer machine.

## com.amakaflow.production-readiness-digest.plist

AMA-1853 / Production-Ready v1. Fires `scripts/production-readiness-digest.sh` daily at 05:00 US Central (10:00 UTC).

### Install

```bash
cp scripts/launchd/com.amakaflow.production-readiness-digest.plist \
   ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist
plutil -lint ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist
```

### Trigger manually

```bash
launchctl kickstart -k gui/$(id -u)/com.amakaflow.production-readiness-digest
# or:
scripts/production-readiness-digest.sh
```

### Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist
rm ~/Library/LaunchAgents/com.amakaflow.production-readiness-digest.plist
```

### Logs

- Script log: `/Volumes/SSD1/openclaw/logs/production-digest.log`
- launchd stdout: `/Volumes/SSD1/openclaw/logs/production-digest.launchd.log`
- launchd stderr: `/Volumes/SSD1/openclaw/logs/production-digest.launchd.err.log`

### Required secrets

- `~/.claude/channels/telegram/.env` → `TELEGRAM_BOT_TOKEN`
- `~/.claude/projects/-Users-davidmini/secrets/keys.env` → `LINEAR_API_KEY`
- `gh` CLI must be authenticated with read access to both `Amakaflow/amakaflow-ios-app` and `Amakaflow/amakaflow-backend`

### Memory references

- `swift6-actor-class-deinit-crash.md` — unrelated; just an example of how memory files are used
- `openclaw-symlink-guard-workaround.md` — pattern this plist deliberately avoids (no symlinked WorkingDirectory)
