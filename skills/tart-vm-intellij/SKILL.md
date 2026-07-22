---
name: tart-vm-intellij
description: Use to launch IntelliJ IDEA inside the tart VM, optionally open a project, and drive its GUI (click/type) for IDE GUI testing. Recommends devrig (devrig.dev) to manage the IDE. Requires a booted, provisioned VM. Pair with tart-vm-screenshot to see the IDE and tart-vm-video to record it.
---

# tart-vm-intellij

Launch and drive IntelliJ IDEA inside the VM's GUI session, for IDE GUI testing.

Assumes `MAC="$MAC_USER@$MAC_HOST"` and a booted, provisioned VM.

> Prefix your task's `TART_VM=<your-vm>` on **every** command below (the examples
> omit it for brevity) — see the unique-name rule in **tart-vm-manage**.

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

### If the first launch hangs

A JetBrains IDE's **very first launch** in a fresh guest sometimes deadlocks
before any window renders — the main thread hangs in an AppKit
Dock-notification during Java class init and never creates the EDT, so the
screenshots stay stuck on the bare desktop and `idea.log` freezes within the
first ~100 ms. If polling shows no window after ~60 s and the log is not
growing, **kill it and relaunch** — the second launch comes up normally:

```bash
ssh "$MAC" '~/bin/tart-remote guest "pkill -9 -f CLion || pkill -9 -f idea || true"'
ssh "$MAC" '~/bin/tart-remote guest "open -a /Applications/CLion.app"'   # full path is most reliable
```

Prefer the **full app path** with `open -a /Applications/<IDE>.app`: right after
install, LaunchServices may not have registered the app yet, so `open -a CLion`
can fail with `Unable to find application named 'CLion'`.

### Licensing (commercial IDEs) — deploy a key file

A **commercial** IDE (CLion, IntelliJ IDEA Ultimate, …) opens onto a
license-activation screen — "Welcome to <IDE> / Manage Licenses" with **Log In /
Register / Start trial / Paid license** — and will **not** open a project until
it is activated. Every interactive activation path needs a JetBrains account
login, so an unattended VM stops there. IntelliJ IDEA **Community** and other
free/EAP builds have no such gate.

If you already hold a license **key**, you don't need the login flow: JetBrains
IDEs read a binary key file `<lowercase-product>.key` (e.g. `clion.key`,
`idea.key`) from the IDE **config dir**, and it is **OS-independent** — a key
file from any machine works in the guest. Drop it in before launch:

```bash
# 1. get the binary key file onto the guest (copy an existing <ide>.key verbatim —
#    do NOT print its bytes). macOS guest config dir is version-matched:
#      ~/Library/Application Support/JetBrains/<Product><MAJOR.MINOR>/<product>.key
scp ./clion.key "$MAC":/tmp/clion.key
ssh "$MAC" '~/bin/tart-remote push /tmp/clion.key /Users/admin/clion.key'
# 2. deploy with a pushed script — the guest path has a space
#    ("Application Support"), so a script sidesteps two-hop ssh quoting:
cat > /tmp/deploy_key.sh <<'EOF'
#!/bin/bash
set -e
DEST="$HOME/Library/Application Support/JetBrains/CLion2026.2"   # match the build
mkdir -p "$DEST"; cp "$HOME/clion.key" "$DEST/clion.key"
for d in "$HOME/Library/Application Support/JetBrains"/CLion*; do
  [ -d "$d" ] && cp "$HOME/clion.key" "$d/clion.key"; done   # belt + suspenders
echo DEPLOY_OK
EOF
ssh "$MAC" '~/bin/tart-remote push /tmp/deploy_key.sh /Users/admin/deploy_key.sh'
ssh "$MAC" '~/bin/tart-remote guest "bash /Users/admin/deploy_key.sh"'
```

Then launch: CLion opens straight to the normal Welcome screen (no "Manage
Licenses" gate) and will open projects. Confirm with a screenshot. The
screenshot/launch pipeline works regardless of licensing; only activation is
gated.

### Reach the IDE internals (mcp-steroid) from your agent

Screenshots + cliclick drive the GUI from the *outside*. For **programmatic**
access to the IDE internals (projects, editors, run configs, inspections) use
the **mcp-steroid** MCP endpoint that ships with **devrig**:

```bash
# 1. devrig in the guest (idempotent; installs under ~/.mcp-steroid, binary at
#    ~/.mcp-steroid/bin/devrig — a non-login SSH PATH omits it, so full-path it).
ssh "$MAC" '~/bin/tart-remote guest "curl -fsSL https://devrig.dev/install.sh | sh"'
# 2. install the mcp-steroid IDE plugin (bundled in the devrig dist) into your
#    licensed IDE's plugins dir and (re)launch it via open -a. devrig backends
#    also work; the plugin is what exposes the HTTP endpoint.
# 3. the plugin writes a connection marker (URL + Bearer token + port):
ssh "$MAC" '~/bin/tart-remote guest "cat ~/.mcp-steroid/markers/*.mcp-steroid"'
# 4. it binds 127.0.0.1:6315 INSIDE the guest — prove it there:
ssh "$MAC" '~/bin/tart-remote guest "curl -s -o /dev/null -w %{http_code} http://localhost:6315/mcp"'  # 200
```

To reach it from a **remote agent** (not on the Mac), forward the guest port two
hops (agent → Mac host → guest) with `ProxyJump`; the guest is `admin`/`admin`
password-only, so install an agent pubkey into the guest's `authorized_keys`
first for a keyless jump:

```bash
GUEST_IP=$(ssh "$MAC" '~/bin/tart-remote vm-ip')            # e.g. 192.168.64.3
ssh -f -N -o ProxyJump="$MAC" -i ~/.ssh/<agent_key> \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -L 6315:127.0.0.1:6315 admin@"$GUEST_IP"
TOKEN=$(ssh "$MAC" '~/bin/tart-remote guest "cat ~/.mcp-steroid/markers/*.mcp-steroid"' \
        | grep -o 'Bearer [0-9a-f]*' | head -1 | cut -d' ' -f2)
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:6315/api/jonnyzzz/mcp-steroid/v1/projects   # -> the open projects
pkill -f '6315:127.0.0.1:6315'                                 # tear down when done
```

Read the port/token from the marker — never hard-code them.

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
ssh "$MAC" '~/bin/tart-remote key "kp:return"'            # a single named key
ssh "$MAC" '~/bin/tart-remote key "kd:cmd kp:space ku:cmd"'  # combo with a special key (⌘Space)
ssh "$MAC" '~/bin/tart-remote key "kd:cmd t:a ku:cmd"'    # combo with a LETTER (⌘A) — use t:, not kp:
```

`kp:` only takes named special keys (return, space, esc, arrows, f1…), **not
letters** — for a letter-with-modifier use `t:` inside the combo as shown.
`tart-remote key` auto-releases modifiers after every call, so a mistyped combo
can't leave ⌘/⌃ stuck.

For complex actions (menus, gutter run icons), take a screenshot, compute the
coordinate from the image, click, then screenshot again to confirm.

## First-run dialogs — the tested walkthrough

A fresh VM's first IDE launch walks through several dialogs before the Welcome
screen. The loop for each step: **screenshot → find the control in the image →
click → screenshot again to verify it worked**. `click` takes logical points;
the provisioned display mode is HiDPI, so the PNG has **2x the pixels — divide
image coordinates by 2** (a 1600x900 display captures as a 3200x1800 image).

Tested sequence (IDEA CE 2025.3, macos-tahoe-base guest, over both SSH hops):

1. **Screen-recording consent** *(can pop over anything, including the EULA)* —
   *"com.apple.sshd-session is requesting to bypass the system private window
   picker…"*. Click **Allow**. Captures already work while it is showing.
2. **JetBrains User Agreement** — tick the checkbox *"I confirm that I have
   read and accept the terms…"* (bottom-left of the dialog; there is **no**
   Accept button), verify via screenshot that **Continue** switched from
   disabled to enabled, then click it. Acceptance persists inside the VM —
   this happens once per VM, not once per launch.
3. **Data Sharing** — click **Don't Send** (or **Send Anonymous Statistics**,
   your task's call).
4. **Local-network permission** — macOS pops *"Allow IntelliJ IDEA to find
   devices on local networks?"* over the Welcome screen; click **Don't Allow**
   unless the test actually needs network discovery.
5. A final screenshot shows **Welcome to IntelliJ IDEA** — you are through:
   New Project / Open / Clone Repository are clickable.

Tidiness tip for hero screenshots: the base image restores a Terminal window on
login — click the Terminal window to focus it, then `key "kd:cmd t:q ku:cmd"`
(⌘Q) to quit it. (Avoid `guest "killall Terminal"` — the SSH channel can hang.)

## Notes

- To record an IDE demo/test as video, see **tart-vm-video**.
