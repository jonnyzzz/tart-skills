---
name: tart-remote-setup
description: Use FIRST, before any other tart-skills skill - establishes the SSH connection from this (Linux) agent to the Apple-Silicon Mac host, installs the tart-remote orchestrator there, and verifies tart is ready. Required once per Mac host.
---

# tart-remote-setup

You (the agent) run on Linux. Tart VMs only run on Apple Silicon macOS, so you
drive them through **one SSH hop to a Mac host**, which runs the `tart-remote`
orchestrator. This skill establishes that hop and installs the orchestrator.

```
[ you: Linux agent ] --ssh--> [ Mac host: tart-remote + tart ] --> [ macOS GUI VM ]
```

## Inputs you need

- `MAC_HOST` — hostname/IP of the Apple-Silicon Mac (has Remote Login enabled)
- `MAC_USER` — your login on that Mac
- SSH key access to `MAC_USER@MAC_HOST` (password auth also works but key is better)

Set a convenience variable and use it everywhere:

```bash
MAC="$MAC_USER@$MAC_HOST"
```

## Steps

1. **Verify you can reach the Mac and it is Apple Silicon with tart:**
   ```bash
   ssh "$MAC" 'uname -m; sw_vers -productVersion; which tart || echo NO-TART'
   ```
   Expect `arm64`. If `NO-TART`, install Tart on the Mac. Two ways:
   - **With Homebrew:** `brew install cirruslabs/cli/tart`
   - **Brew-less (no Xcode Command Line Tools needed)** — download the release
     binary directly; this is the most portable and works on a bare macOS VM:
     ```bash
     ssh "$MAC" '
       mkdir -p ~/bin ~/tart
       curl -fsSL https://github.com/cirruslabs/tart/releases/latest/download/tart.tar.gz -o /tmp/tart.tar.gz
       tar xzf /tmp/tart.tar.gz -C ~/tart
       ln -sf ~/tart/tart.app/Contents/MacOS/tart ~/bin/tart
       ~/bin/tart --version'
     ```
   `tart-remote` puts `~/bin`, `/opt/homebrew/bin`, and `/usr/local/bin` on PATH,
   so either install location works. **`sshpass` is optional** — if it is not
   installed, `tart-remote` falls back to OpenSSH's `SSH_ASKPASS` for the inner
   (Mac→guest) hop, so `tart` + stock `ssh` are the only hard dependencies.

2. **Install the orchestrator + provisioning on the Mac** (copy this repo's
   `bin/tart-remote` and `provision/provision.sh`). From the repo root:
   ```bash
   ssh "$MAC" 'mkdir -p ~/bin ~/.tart-remote'
   scp bin/tart-remote "$MAC":~/bin/tart-remote
   ssh "$MAC" 'mkdir -p ~/tart-skills/provision'
   scp provision/provision.sh "$MAC":~/tart-skills/provision/provision.sh
   ssh "$MAC" 'chmod +x ~/bin/tart-remote ~/tart-skills/provision/provision.sh'
   ```
   `tart-remote` finds `provision.sh` at `../provision/provision.sh` relative to
   itself, so keep the layout, or export `TART_PROVISION=/path/to/provision.sh`.

3. **Confirm the orchestrator runs** (PATH note: `~/bin` may not be on a
   non-login SSH shell's PATH — call it by full path or add it):
   ```bash
   ssh "$MAC" '~/bin/tart-remote vm-status'
   ```
   You should see `exists=no running=no` for a fresh host.

4. **(If Remote Login is off)** ask a human to enable it on the Mac
   (System Settings → General → Sharing → Remote Login), or run on the Mac:
   `sudo systemsetup -setremotelogin on`.

## Preferred invocation pattern for every later skill

```bash
ssh "$MAC" '~/bin/tart-remote <subcommand> [args]'
```

Data-returning subcommands (`screenshot -`, `record N -`, `vm-ip`) stream clean
bytes to stdout; all logs go to stderr, so you can redirect stdout to a file:

```bash
ssh "$MAC" '~/bin/tart-remote screenshot -' > shot.png
```

Once setup succeeds, continue with **tart-vm-manage** to boot a VM.
