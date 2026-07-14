---
name: tart-vm-screenshot
description: Use to capture a screenshot of the macOS GUI running inside the tart VM and bring the PNG back to this agent - your "eyes" for GUI testing (verify a window opened, read on-screen state, check UI layout). Requires a booted, provisioned VM.
---

# tart-vm-screenshot

Capture the VM's screen so you can *see* what the GUI is doing. This is your
primary feedback loop for GUI testing: act (launch app / click) → screenshot →
verify → act again.

Assumes `MAC="$MAC_USER@$MAC_HOST"` and a booted, provisioned VM (see
tart-vm-manage). Uses macOS `screencapture -x` inside the guest; the TCC grant
from provisioning is what makes an SSH-triggered capture contain the real screen
instead of a black frame.

> Prefix your task's `TART_VM=<your-vm>` on **every** command below (the examples
> omit it for brevity) — see the unique-name rule in **tart-vm-manage**.

## Capture straight to a local file (recommended)

`screenshot -` writes the raw PNG to stdout; logs go to stderr, so redirect:

```bash
ssh "$MAC" '~/bin/tart-remote screenshot -' > shot.png
file shot.png    # -> PNG image data, 1600 x 900 ...  (matches TART_DISPLAY)
```

Then **read the PNG** with your image-viewing tool to inspect the GUI state.

## Capture to a file on the Mac host (for later pull)

```bash
ssh "$MAC" '~/bin/tart-remote screenshot layout.png'   # -> prints host path under ~/.tart-remote/artifacts/
ssh "$MAC" '~/bin/tart-remote screenshot /tmp/full.png'
scp "$MAC":/tmp/full.png ./full.png
```

## GUI-testing loop example

```bash
ssh "$MAC" '~/bin/tart-remote start-ide'        # launch IntelliJ
sleep 20
ssh "$MAC" '~/bin/tart-remote screenshot -' > ide-splash.png   # verify it appeared
# ... read ide-splash.png, decide next action ...
ssh "$MAC" '~/bin/tart-remote click 800 450'    # click something
ssh "$MAC" '~/bin/tart-remote screenshot -' > after-click.png  # verify result
```

For launching and driving IntelliJ specifically, see **tart-vm-intellij**.

## Tips

- The image is the guest's **logical** resolution (`TART_DISPLAY`, default
  1600x900). Set a fixed resolution in tart-vm-manage so coordinates for
  `click`/`type` stay stable between runs.
- If a capture is all-black: the VM likely was not provisioned (no TCC grant) —
  run `tart-remote provision`, or the GUI session had not finished login (wait
  and retry).
- **macOS 15+/26 periodic consent dialog.** After provisioning, `screencapture`
  works, but macOS periodically shows *"com.apple.sshd-session is requesting to
  bypass the system private window picker and directly access your screen"* with
  an **Allow** button. Captures still succeed, but the dialog sits on top and
  pollutes the frame. Detect it in a screenshot and clear it with a click on
  Allow, e.g. (coords depend on `TART_DISPLAY`; at 1600x900 it is ~center):
  ```bash
  ssh "$MAC" '~/bin/tart-remote click 800 423'   # click "Allow"
  ```
  This is periodic (roughly weekly), not per-capture.
