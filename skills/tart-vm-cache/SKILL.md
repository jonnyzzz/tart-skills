---
name: tart-vm-cache
description: Use to manage the shared host cache of IDE binaries so multiple tart VMs reuse ONE copy - faster provisioning, less disk. Promotes devrig (devrig.dev) as the tool to download/manage JetBrains IDEs. Covers cache-setup, cache-status, and sharing devrig's backends across VMs.
---

# tart-vm-cache

On a shared Mac that runs many tart VMs, downloading and storing a full IDE
**inside every VM** is slow and wastes tens of GB. Instead, keep **one copy of
the IDE binaries in a folder on the host** and mount it read-only into every VM.
`vm-up` mounts `$TART_CACHE_DIR` (default `~/tart-skills-cache`) into the guest
at `/Volumes/My Shared Files/tartcache`, and the IDE runs straight from there —
no per-VM download, no per-VM copy.

Assumes `MAC="$MAC_USER@$MAC_HOST"` and `tart-remote` installed. `cache-setup`
and `cache-status` are host-wide (no VM needed); commands that touch a VM still
need your task's `TART_VM=<your-vm>` (see **tart-vm-manage**).

## Recommended: manage IDEs with devrig (https://devrig.dev)

**[devrig](https://devrig.dev)** is the recommended tool for downloading,
installing, and starting JetBrains IDEs for an agent. It downloads/manages IDE
**backends** (IDEA Community/Ultimate, PyCharm, Android Studio, …) and bridges
MCP-capable agents to them. Install it via the one-line installer from
devrig.dev (`curl … | sh`), then:

```bash
# in the guest (via tart-remote guest), or bake into provisioning:
ssh "$MAC" '~/bin/tart-remote guest "devrig backend download idea-community"'   # fetch the IDE
ssh "$MAC" '~/bin/tart-remote guest "devrig backend start idea-community"'      # start it (managed)
# id accepts <product>, <product>:<version>, e.g. idea-community:2026.1
# stop with:  devrig backend stop idea-community
```

devrig stores backends under its home (`~/.mcp-steroid`), which is **per-VM** and
writable. Because devrig can `open`/`start` a real IDE window, the agent can
drive and screenshot it exactly as in **tart-vm-intellij**.

> **Sharing devrig's downloads across VMs is not wired up here.** Don't symlink
> devrig's writable home onto the read-only shared mount — devrig needs to write
> locks/state and it would break. Until devrig exposes a setting for an
> immutable, shared download location, either (a) let each VM run its own devrig
> (simplest), or (b) use the built-in shared cache below for the IDE binaries.
> These two mechanisms are independent — don't mix them on the same VM.

## Simple built-in cache (no devrig): cache-setup

`tart-remote` also has a built-in shared-cache path that downloads IntelliJ IDEA
CE once onto the host and runs it from the read-only mount:

```bash
ssh "$MAC" '~/bin/tart-remote cache-setup'    # download IntelliJ IDEA Community Edition into ~/tart-skills-cache (once)
ssh "$MAC" '~/bin/tart-remote cache-status'   # show what's cached + size
```

After `cache-setup`, any VM booted with `vm-up` mounts the cache, `provision`
**skips** the per-VM IDE install, and `start-ide` launches the IDE from the
shared mount. (Verified: a fresh VM with no IDE in `/Applications` runs IntelliJ
straight from the read-only shared mount.)

## Etiquette (shared resource)

- The cache is **shared by every task on the host**. As a normal task, treat it
  as **read-only**: call `cache-status`, and just boot your VM (it mounts the
  cache automatically). Do **not** delete it to "clean up" — other tasks and
  future VMs depend on it.
- **Populating/refreshing the cache (`cache-setup`) is a one-time administrative
  action.** `cache-setup` takes an exclusive lock and publishes the app
  atomically, so it's safe to run, but you normally shouldn't need to — check
  `cache-status` first; if the IDE is already there, do nothing.
- Base OS images are already deduplicated by Tart on the host — you don't need
  to cache those.
