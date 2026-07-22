#!/usr/bin/env bash
# provision.sh — guest-side provisioning for a tart-skills GUI-testing VM.
# Runs INSIDE the tart macOS guest over SSH (copied there by `tart-remote
# provision`). Idempotent: safe to re-run. Minimal by design — just what a
# GUI-driving agent needs: capture tooling, a UI-automation tool, IntelliJ,
# and the TCC grant that lets an SSH session drive the screen.
set -euo pipefail
log() { echo "[provision] $(date -u +%FT%TZ) $*"; }

# 1. Homebrew (cirruslabs base images ship it, but be safe on a bare image)
if ! command -v brew >/dev/null 2>&1; then
  log "installing Homebrew (NONINTERACTIVE)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/tmp/brew-install.log 2>&1
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
grep -q 'brew shellenv' ~/.zprofile 2>/dev/null \
  || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
# A NON-interactive SSH command (`ssh host 'cmd'`) sources ONLY ~/.zshenv, not
# ~/.zprofile — so put the brew PATH there too, or cliclick/ffmpeg won't resolve
# when the orchestrator drives the GUI over SSH.
grep -q 'brew shellenv' ~/.zshenv 2>/dev/null \
  || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshenv

# 2. GUI-driving + capture tooling
#    cliclick     — synthetic mouse/keyboard for UI automation
#    displayplacer — force a stable logical resolution (screenshots stay consistent)
#    ffmpeg       — transcode the raw screencapture .mov to a compact .mp4 in-guest
log "installing cliclick + displayplacer + ffmpeg..."
brew install cliclick displayplacer ffmpeg 2>&1 | tail -2 || true

# 2b. Pin the guest's logical resolution. tart's `--display WxH` sets up the
#     virtual display, but a macOS 26 guest boots its GUI at 1024x768 scaled
#     anyway — click coordinates and screenshot sizes then drift between runs.
#     Pin the mode from inside the guest (idempotent; TART_DISPLAY_SIZE is
#     passed by `tart-remote provision`, default 1600x900). The pinned mode is
#     HiDPI, so screenshots come out at 2x the logical size (1600x900 -> 3200x1800).
WANT_RES="${TART_DISPLAY_SIZE:-1600x900}"
DP="$(command -v displayplacer || true)"
if [ -n "$DP" ]; then
  SCREEN_ID="$("$DP" list 2>/dev/null | awk '/^Persistent screen id:/ {print $4; exit}')"
  CUR_RES="$("$DP" list 2>/dev/null | awk '/^Resolution:/ {print $2; exit}')"
  if [ -n "$SCREEN_ID" ] && [ "$CUR_RES" != "$WANT_RES" ]; then
    if "$DP" "id:$SCREEN_ID res:$WANT_RES hz:60 color_depth:7 scaling:on" 2>/dev/null \
       || "$DP" "id:$SCREEN_ID res:$WANT_RES scaling:on" 2>/dev/null \
       || "$DP" "id:$SCREEN_ID res:$WANT_RES" 2>/dev/null; then
      log "display pinned to $WANT_RES (was $CUR_RES)"
    else
      log "WARN: could not pin display to $WANT_RES (still $CUR_RES) — click coords may drift"
    fi
  else
    log "display already $CUR_RES"
  fi
else
  log "WARN: displayplacer missing — cannot pin display resolution"
fi

# 3. IntelliJ IDEA Community (the app under GUI test). CE bundles its own JBR,
#    so no separate JDK is needed just to launch the IDE.
CACHE_IDE_DIR="/Volumes/My Shared Files/tartcache/ide"
if ls -d "$CACHE_IDE_DIR"/IntelliJ*.app >/dev/null 2>&1; then
  # The host shared cache already has the IDE (mounted read-only by vm-up). Skip
  # the per-VM download/install — the IDE runs straight from the shared mount.
  log "shared IDE found in host cache ($CACHE_IDE_DIR) — skipping per-VM IntelliJ install"
elif ! ls -d /Applications/IntelliJ*.app >/dev/null 2>&1; then
  log "installing IntelliJ IDEA Community (cask; large download)..."
  brew install --cask intellij-idea-ce 2>&1 | tail -3 || true
fi
# De-quarantine the app: a cask-installed app is flagged "downloaded from the
# Internet", so the FIRST `open` pops a Gatekeeper "are you sure?" dialog that
# blocks the launch until clicked. Stripping com.apple.quarantine skips it, so
# `tart-remote start-ide` opens straight into the IDE. (Verified: the dialog
# appears without this.)
for app in /Applications/IntelliJ*.app; do
  [ -e "$app" ] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
done

# 4. TCC ScreenCapture grant for the SSH session's process.
#    Without this, `screencapture` over SSH returns a black/empty frame (or the
#    OS silently blocks it). The cirruslabs base images ship with SIP OFF, so we
#    can write the TCC.db directly. Grant kTCCServiceScreenCapture to the sshd
#    session client so screenshots/video captured over SSH contain the real screen.
log "granting TCC ScreenCapture to com.apple.sshd-session..."
TCC_USER="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
TCC_SYS="/Library/Application Support/com.apple.TCC/TCC.db"
SQL="
INSERT OR REPLACE INTO access
  (service, client, client_type, auth_value, auth_reason, auth_version,
   indirect_object_identifier_type, indirect_object_identifier, flags, last_modified)
  VALUES ('kTCCServiceScreenCapture', 'com.apple.sshd-session', 0, 2, 2, 1, 0, 'UNUSED', 0, strftime('%s','now'));
"
sqlite3 "$TCC_USER" "$SQL" 2>&1 || log "user TCC update may have schema mismatch"
sudo sqlite3 "$TCC_SYS" "$SQL" 2>&1 || log "system TCC update needs sudo; skipping"

# AppleEvents grant for the ssh key-gen wrapper — lets an SSH session drive apps
# (e.g. AppleScript window positioning) without an interactive consent dialog.
SQL_AE="
INSERT OR REPLACE INTO access
  (service, client, client_type, auth_value, auth_reason, auth_version,
   indirect_object_identifier_type, indirect_object_identifier, flags, last_modified)
  VALUES ('kTCCServiceAppleEvents', '/usr/libexec/sshd-keygen-wrapper', 1, 2, 2, 1, 0, 'com.apple.systemevents', 0, strftime('%s','now'));
"
sqlite3 "$TCC_USER" "$SQL_AE" 2>&1 || log "AppleEvents TCC grant failed (schema mismatch?)"

# Verify the ESSENTIAL tool before claiming success — cliclick is what makes GUI
# driving possible; if it's missing the VM is not usable for GUI testing.
if ! command -v cliclick >/dev/null 2>&1; then
  log "FATAL: cliclick did not install — not marking provisioned"
  exit 1
fi
# Find the IDE without a `| head` pipeline: under `set -o pipefail` + `set -e`,
# `ls ... | head -1` aborts the whole script — `head` closes the pipe after one
# line, `ls` dies of SIGPIPE (141), pipefail propagates it, and `set -e` fires
# on THIS line, one step before the provisioned marker below (so provisioning
# did all its work but exited 1 and never marked the VM). A glob loop takes the
# first match with no pipe and no SIGPIPE.
IDE_LOC=none
for _ide in "$CACHE_IDE_DIR"/IntelliJ*.app /Applications/IntelliJ*.app; do
  [ -e "$_ide" ] || continue
  IDE_LOC="$_ide"
  break
done
touch "$HOME/.tart-skills-provisioned"
log "done. cliclick=$(command -v cliclick), ffmpeg=$(command -v ffmpeg || echo MISSING), IDE=$IDE_LOC"
