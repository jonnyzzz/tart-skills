---
name: tart-vm-intellij
description: Use to launch IntelliJ IDEA inside the tart VM, optionally open a project, and drive its GUI (click/type) for IDE GUI testing. Recommends devrig (devrig.dev) to manage the IDE. Requires a booted, provisioned VM. Pair with tart-vm-screenshot to see the IDE and tart-vm-video to record it.
---

# tart-vm-intellij

Launch and drive IntelliJ IDEA inside the VM's GUI session, for IDE GUI testing.

Assumes `MAC="$MAC_USER@$MAC_HOST"` and a booted, provisioned VM.

## Managing the IDE — use devrig (recommended)

**[devrig](https://devrig.dev)** is the recommended tool for getting a JetBrains
IDE onto the VM: it downloads, installs, and starts managed IDE backends and
bridges MCP-capable agents to them. Prefer it over ad-hoc installs:

```bash
ssh "$MAC" '~/bin/tart-remote guest "devrig backend download idea-community"'  # once
ssh "$MAC" '~/bin/tart-remote guest "devrig backend start idea-community"'     # start managed IDE
```

Share devrig's downloaded backends across VMs via the shared host cache — see
**tart-vm-cache**. To make the IDE window visible for screenshots/video, launch
it into the GUI session with `open -a` (see below); a bare `devrig backend
start` from an SSH shell can hit `HeadlessException`, so `open -a` the managed
app is the reliable way to get an on-screen window.

The built-in `tart-remote start-ide` (below) works too and automatically prefers
a shared-cache IDE if one is mounted.

## Why `open -a`, not `ssh ... idea`

A Java GUI app launched directly from an SSH shell has no Aqua desktop context
and dies with `java.awt.HeadlessException`. `tart-remote start-ide` uses macOS
`open -a`, which routes through launchd into the auto-logged-in user's GUI
session — so the IDE gets a real desktop and windows render. (Learned the hard
way in the source project.)

## Launch

```bash
ssh "$MAC" '~/bin/tart-remote start-ide'                       # welcome screen
ssh "$MAC" '~/bin/tart-remote start-ide /Users/admin/myproj'   # open a project
```

Then **watch it come up** — indexing takes time; poll with screenshots:

```bash
for i in 1 2 3 4 5 6; do
  sleep 15
  ssh "$MAC" '~/bin/tart-remote screenshot -' > ide-$i.png
  # inspect ide-$i.png; stop once the editor/project view is ready
done
```

## Get a project into the VM first (if needed)

```bash
# copy a local project up to the Mac, then push it INTO the guest
scp -r ./myproj "$MAC":/tmp/myproj
ssh "$MAC" '~/bin/tart-remote guest "mkdir -p ~/Work"'
ssh "$MAC" '~/bin/tart-remote push /tmp/myproj /Users/admin/Work/myproj'   # host -> guest
```
(Or share a host dir at boot with `TART_DIR=name:/host/path` in tart-vm-manage.)

## Drive the IDE GUI

Use screenshots to locate targets, then cliclick via tart-remote:

```bash
ssh "$MAC" '~/bin/tart-remote click 820 470'      # click at screen coords
ssh "$MAC" '~/bin/tart-remote type "MyTest"'      # type into focused field
ssh "$MAC" '~/bin/tart-remote key "cmd+space"'    # keystroke / combo
```

For complex actions (menus, gutter run icons), take a screenshot, compute the
coordinate from the image, click, then screenshot again to confirm.

## Notes

- First launch may show a JetBrains privacy/EULA dialog — screenshot to detect
  it and click "Accept", or pre-seed IDE config via `tart-remote guest`.
- To record an IDE demo/test as video, see **tart-vm-video**.
