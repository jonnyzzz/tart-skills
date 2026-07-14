---
name: tart-vm-manage
description: Use to create, boot, provision, check, stop, or delete a tart macOS VM on the remote Mac host - the VM lifecycle "service". Boots a full-GUI macOS session that survives your SSH session closing. Covers shared-host etiquette and cleanup. Run tart-remote-setup first.
---

# tart-vm-manage

Manage the lifecycle of a full-GUI macOS tart VM on the Mac host. The VM is a
supervised resource: `vm-up` boots it **detached**, so it keeps running (and
keeps its GUI session alive) after your SSH command returns and your agent
connection closes. This is the "keep the VM alive" management layer.

## ⚠️ The Mac host is SHARED — be a good neighbor

Other agents and tasks use the SAME Mac. Follow these rules or you WILL disrupt
them:

1. **Use a UNIQUE VM name per task.** Never rely on the default `tart-skills-vm`
   when others may be active — pick a name tied to your task, e.g.
   `TART_VM=tart-skills-<task-id>`. Set it on EVERY command.
2. **Check who's already there first:** `ssh "$MAC" '~/bin/tart-remote ls'`
   lists all VMs. Only ever stop/delete/inspect a VM **you** created.
3. **Always clean up when done** — see "Clean up" below. A leaked running VM
   eats a neighbor's RAM/CPU.
4. **Size modestly.** Don't grab all cores/RAM (`TART_CPU`/`TART_MEMORY`); leave
   headroom for others.
5. **Never delete the shared IDE cache** (`~/tart-skills-cache`; see
   **tart-vm-cache**) or the base images, and never `vm-gc` a VM you didn't
   create.

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
new HostKey").

- **Preferred:** keep the keychain unlocked on the host once (a GUI login
  session, or a host-side `security unlock-keychain` as part of host setup). Then
  no password is needed on any command. Linux guests never need this.
- **Otherwise:** pass the host user's **login** password so `vm-up` unlocks it —
  but note this puts the password on the command line (visible in the host's
  process list); use only on a trusted host:
  ```bash
  ssh "$MAC" "TART_VM=<your-vm> TART_KEYCHAIN_PW='<host-login-pw>' ~/bin/tart-remote vm-up"
  ```
  If the supplied password can't unlock the keychain, `vm-up` aborts (the guest
  wouldn't boot anyway).

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

5. **Clean up (REQUIRED when your task is done):**
   ```bash
   ssh "$MAC" 'TART_VM=<your-vm> ~/bin/tart-remote vm-gc'    # stop + delete YOUR VM
   ```
   Use `vm-down` (stop, keep the disk) only if you will resume the same VM
   shortly; otherwise `vm-gc` to reclaim the disk. Do this even if your task
   failed. Then confirm nothing of yours lingers: `~/bin/tart-remote ls`.
   Leave other tasks' VMs and the shared cache alone.

## Notes

- The VM boots `--no-graphics`: no window on the Mac, but a **complete macOS
  GUI session** runs inside (auto-logged-in `admin`, WindowServer + Aqua). That
  is what makes GUI testing possible — you see it via `tart-vm-screenshot` and
  drive it via cliclick / `tart-vm-intellij`.
- To *watch* it live from a human Mac, run on the host:
  `tart run --vnc-experimental "$TART_VM"`.
- Once up + provisioned, use **tart-vm-screenshot**, **tart-vm-intellij**, and
  **tart-vm-video**.
