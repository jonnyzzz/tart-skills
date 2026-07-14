---
name: tart-vm-video
description: Use to record a screen-capture video of the macOS GUI inside the tart VM (e.g. an IntelliJ GUI test or demo run) and bring the .mov/.mp4 back to this agent. Requires a booted, provisioned VM.
---

# tart-vm-video

Record the VM's GUI as video — for capturing a GUI test run, reproducing a bug
on camera, or producing a demo. Uses macOS `screencapture -V` inside the guest,
wrapped in `caffeinate` so the display never sleeps mid-capture (which produced
frozen/identical frames in the source project).

Assumes `MAC="$MAC_USER@$MAC_HOST"` and a booted, provisioned VM.

> Prefix your task's `TART_VM=<your-vm>` on **every** command below (the examples
> omit it for brevity) — see the unique-name rule in **tart-vm-manage**.

## Record and pull the raw .mov to a local file

`record SECS -` streams the raw `.mov` to stdout (logs to stderr):

```bash
ssh "$MAC" '~/bin/tart-remote record 20 -' > demo.mov     # 20-second capture
ffprobe demo.mov                                          # verify duration/size
```

## Record to a file on the Mac host, then transcode + pull

```bash
ssh "$MAC" '~/bin/tart-remote record 30 take.mov'         # -> host path under ~/.tart-remote/artifacts/
scp "$MAC":~/.tart-remote/artifacts/take.mov ./take.mov    # pull the raw .mov
# transcode to a compact mp4 wherever you have ffmpeg (your agent machine here;
# ffmpeg is installed inside the guest, but not necessarily on the Mac host):
ffmpeg -y -v error -i ./take.mov \
       -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart -an \
       ./take.mp4
```

To transcode inside the guest instead (guest has ffmpeg from provisioning), run
it via `guest` before pulling the smaller `.mp4`.

## Recording a GUI test end-to-end

Start the recording, then drive the GUI while it captures. `record` blocks for
`SECS`, so kick off the action in the background or size the window to cover it:

```bash
# 1. get the IDE ready BEFORE recording (indexing is slow and boring on camera)
ssh "$MAC" '~/bin/tart-remote start-ide /Users/admin/Work/myproj'
sleep 60   # let it index; confirm with a screenshot

# 2. record while you drive the test (run in background so you can act during it)
ssh "$MAC" '~/bin/tart-remote record 45 run.mov' > /dev/null &
sleep 2
ssh "$MAC" '~/bin/tart-remote click 60 300'     # e.g. click a gutter run icon
# ... more clicks/keys to exercise the GUI test ...
wait                                            # recording finishes at 45s
scp "$MAC":~/.tart-remote/artifacts/run.mov ./run.mov
```

## Notes

- `screencapture -V SECS` always runs its **full timer** regardless of when your
  action finishes — size `SECS` to the action time plus margin.
- The raw `.mov` is ~25 MB/min. Transcode to `.mp4` (CRF ~20) for a small,
  shareable file; keep only the mp4.
- Capture resolution follows `TART_DISPLAY` (default 1600x900).
