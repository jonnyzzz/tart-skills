---
name: tart-vm-manage
description: Use to create, boot, provision, check, stop, or delete a tart macOS VM on the remote Mac host - the VM lifecycle "service". Boots a full-GUI macOS session that survives your SSH session closing. Run tart-remote-setup first.
---

# tart-vm-manage

Manage the lifecycle of a full-GUI macOS tart VM on the Mac host. The VM is a
supervised resource: `vm-up` boots it **detached**, so it keeps running (and
keeps its GUI session alive) after your SSH command returns and your agent
connection closes. This is the "keep the VM alive" management layer.

Assumes `MAC="$MAC_USER@$MAC_HOST"` and `tart-remote` installed (see
tart-remote-setup). Prefix every command with `ssh "$MAC" '~/bin/tart-remote ...'`.

## Configuration (optional env, prefix on the remote side)

```bash
# choose VM name, base image, size, logical display resolution
ssh "$MAC" 'TART_VM=my-vm TART_IMAGE=ghcr.io/cirruslabs/macos-tahoe-base:latest \
            TART_CPU=4 TART_MEMORY=8192 TART_DISPLAY=1600x900 ~/bin/tart-remote vm-up'
```
Defaults: `tart-skills-vm`, `macos-tahoe-base:latest`, 4 CPU / 8 GiB / 1600x900.
Keep the SAME `TART_VM` across all calls in a session (export it or repeat it).

**macOS guest on a headless Mac:** Apple's Virtualization.framework won't boot a
*macOS* guest unless the host's `login.keychain` is unlocked — over SSH it is
locked, and `vm-up` fails with a `Code=-9` "security error" ("Failed to create
new HostKey"). Pass the Mac host user's **login** password so `vm-up` unlocks it:
```bash
ssh "$MAC" 'TART_VM=tart-skills-vm TART_KEYCHAIN_PW="<host-login-pw>" ~/bin/tart-remote vm-up'
```
(Or keep a GUI login session active on the Mac. Linux guests don't need this.)

## Lifecycle

1. **Boot (creates + clones on first use, then boots detached, waits for IP):**
   ```bash
   ssh "$MAC" '~/bin/tart-remote vm-up'      # prints the VM IP on success
   ```
   First-ever run pulls the base image (many minutes). `vm-up` is idempotent —
   if the VM is already up it just prints the IP.

2. **Provision once** (installs cliclick, ffmpeg, IntelliJ CE, and the TCC
   screen-recording grant that lets SSH capture the real screen):
   ```bash
   ssh "$MAC" '~/bin/tart-remote provision'
   ```
   Long-running (IntelliJ cask download). Re-running is safe (idempotent).

3. **Check status any time:**
   ```bash
   ssh "$MAC" '~/bin/tart-remote vm-status'
   # -> exists / running / ip / provisioned(yes|no)
   ```

4. **Run an arbitrary command in the guest** (debugging):
   ```bash
   ssh "$MAC" '~/bin/tart-remote guest "sw_vers -productVersion; whoami"'
   ```

5. **Tear down:**
   ```bash
   ssh "$MAC" '~/bin/tart-remote vm-down'    # stop, keep the disk
   ssh "$MAC" '~/bin/tart-remote vm-gc'      # stop + delete the VM entirely
   ```

## Notes

- The VM boots `--no-graphics`: no window on the Mac, but a **complete macOS
  GUI session** runs inside (auto-logged-in `admin`, WindowServer + Aqua). That
  is what makes GUI testing possible — you see it via `tart-vm-screenshot` and
  drive it via cliclick / `tart-vm-intellij`.
- To *watch* it live from a human Mac, run on the host:
  `tart vnc-experimental tart-skills-vm` (or `tart run --vnc-experimental`).
- Once up + provisioned, use **tart-vm-screenshot**, **tart-vm-intellij**, and
  **tart-vm-video**.
