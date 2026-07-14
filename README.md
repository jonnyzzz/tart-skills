# tart-skills

**Agent skills for running GUI tests inside a [Tart](https://tart.run/) macOS VM — driven from Linux over SSH.**

The goal: give an AI agent (running on Linux, or anywhere without Apple Silicon)
a set of workable [skills](https://docs.claude.com/en/docs/claude-code/skills)
to boot a **full-GUI macOS session** in a Tart VM and *drive its UI* — take
screenshots, launch IntelliJ IDEA, click and type, and record video — so it can
run **GUI tests on macOS** without a Mac of its own.

![A live full-GUI macOS session inside a Tart VM, captured over SSH](docs/img/vm-desktop.png)

> *Above: a real screenshot the agent captured over SSH from a headless
> (`--no-graphics`) Tart VM — a complete macOS Aqua session (Finder, Dock,
> wallpaper), not a headless server. This is what makes GUI testing possible.*

## Why this exists

[Tart](https://tart.run/) runs macOS/Linux VMs on Apple Silicon using Apple's
`Virtualization.Framework`. It only runs on an Apple Silicon Mac. An agent that
lives on Linux therefore cannot call `tart` directly — it has to reach a Mac.

`tart-skills` closes that gap with **one SSH hop to a Mac host** plus a small
orchestrator (`tart-remote`) installed there. The agent stays on Linux; all the
Mac- and VM-specific machinery lives behind a clean SSH seam.

```
┌────────────────┐   ssh    ┌──────────────────────────┐          ┌─────────────────────┐
│  Linux agent   │ ───────▶ │  Mac host (Apple Silicon) │  tart +  │  macOS GUI VM       │
│  (the skills)  │          │  bin/tart-remote + tart   │  sshpass │  Aqua session:      │
│                │ ◀─────── │  (boots + supervises VM)  │ ───────▶ │  IntelliJ, Finder…  │
└────────────────┘  stdout  └──────────────────────────┘  ControlM└─────────────────────┘
     PNG / MP4 / IP            the "management service"     mux         screencapture,
                                                                        cliclick, open -a
```

Two SSH hops:

1. **Outer (Linux → Mac):** the agent runs `ssh $MAC_USER@$MAC_HOST 'tart-remote …'`.
2. **Inner (Mac → VM guest):** `tart-remote` uses `sshpass` + SSH `ControlMaster`
   multiplexing to reach the guest (default creds `admin`/`admin`).

## The management layer (the "service")

A Tart VM is a long-lived foreground process (`tart run`). If an agent just SSHed
in and ran it, the VM would die the moment the SSH command returned. `tart-remote`
treats the VM as a **supervised resource**:

- **`vm-up`** boots it *detached* (`nohup … </dev/null & disown`), so the VM — and
  its GUI session — **survives the agent's SSH connection closing**. *(Verified:
  the VM stays `running` after the launching process exits.)*
- State is read straight from Tart (`tart list` / `tart ip`) — no extra bookkeeping.
- The inner SSH connection is multiplexed with `ControlMaster`/`ControlPersist`,
  which avoids macOS sshd's "Too many authentication failures" lockout under the
  rapid connections a driving session makes.

For setups that must survive a host reboot, wrap `tart-remote vm-up` in a
launchd LaunchAgent on the Mac — the orchestrator is designed to be called that
way too (idempotent `vm-up`).

## Skills

Each lives in `skills/<name>/SKILL.md`:

| Skill | Use it to… |
|---|---|
| **[tart-remote-setup](skills/tart-remote-setup/SKILL.md)** | Establish the Linux→Mac SSH hop, install `tart-remote`, verify Tart. **Run first.** |
| **[tart-vm-manage](skills/tart-vm-manage/SKILL.md)** | Create / boot (detached) / provision / status / stop / delete the VM. |
| **[tart-vm-screenshot](skills/tart-vm-screenshot/SKILL.md)** | Capture the VM screen as a PNG — the agent's "eyes". |
| **[tart-vm-intellij](skills/tart-vm-intellij/SKILL.md)** | Launch IntelliJ IDEA, open a project, click/type to drive it. |
| **[tart-vm-video](skills/tart-vm-video/SKILL.md)** | Record the GUI as video (`.mov` → compact `.mp4`). |

## Prerequisites

**On the Mac host** (the one you SSH into):

- Apple Silicon (M1 or newer) Mac.
- **Tart** — either `brew install cirruslabs/cli/tart`, or **brew-less** (no
  Xcode Command Line Tools required), which is what a bare macOS host needs:
  ```bash
  mkdir -p ~/bin ~/tart
  curl -fsSL https://github.com/cirruslabs/tart/releases/latest/download/tart.tar.gz -o /tmp/tart.tar.gz
  tar xzf /tmp/tart.tar.gz -C ~/tart
  ln -sf ~/tart/tart.app/Contents/MacOS/tart ~/bin/tart
  ```
- `sshpass` is **optional**: if absent, `tart-remote` uses OpenSSH's
  `SSH_ASKPASS` for the inner hop. So `tart` + stock `ssh` are the only hard
  dependencies — **no Homebrew required on the Mac**.
- **Remote Login** enabled: System Settings → General → Sharing → Remote Login,
  or `sudo systemsetup -setremotelogin on`.

**On the agent side (Linux):** an SSH client and SSH access to the Mac.

Everything the guest needs (cliclick, ffmpeg, IntelliJ, the screen-recording
grant) is installed by `tart-remote provision`.

### Configure the Mac host (one-time)

On the Apple Silicon Mac you will drive:

1. **Enable Remote Login (SSH):**
   ```bash
   sudo systemsetup -setremotelogin on
   ```
   (or System Settings → General → Sharing → Remote Login).
2. **Give the agent key-based SSH access.** From the agent machine, install your
   public key on the Mac (avoids passwords and keeps sessions unattended):
   ```bash
   ssh-copy-id "$MAC_USER@$MAC_HOST"
   # or append your public key to ~/.ssh/authorized_keys on the Mac by hand
   ssh "$MAC_USER@$MAC_HOST" 'echo ok'     # verify
   ```
   Tip: if your agent offers many keys (e.g. an SSH agent), pin the right one
   with `IdentitiesOnly yes` + `IdentityFile` in `~/.ssh/config`, and add
   `ControlMaster auto` / `ControlPersist` so repeated commands reuse one
   authenticated connection.
3. **Install Tart** (brew or brew-less — see above). No Homebrew, no Xcode
   Command Line Tools, and no other packages are required on the Mac.

## Quick start

```bash
# 0. from the agent, point at your Mac
MAC=me@my-mac.local          # MAC_USER@MAC_HOST

# 1. install the orchestrator on the Mac (from this repo checkout)
ssh "$MAC" 'mkdir -p ~/bin ~/tart-skills/provision'
scp bin/tart-remote            "$MAC":~/bin/tart-remote
scp provision/provision.sh     "$MAC":~/tart-skills/provision/provision.sh
ssh "$MAC" 'chmod +x ~/bin/tart-remote ~/tart-skills/provision/provision.sh'

# 2. boot a full-GUI macOS VM (first run pulls the base image — minutes)
ssh "$MAC" '~/bin/tart-remote vm-up'          # prints the VM IP

# 3. provision it once (cliclick, ffmpeg, IntelliJ CE, screen-recording grant)
ssh "$MAC" '~/bin/tart-remote provision'

# 4. SEE the GUI
ssh "$MAC" '~/bin/tart-remote screenshot -' > desktop.png

# 5. launch IntelliJ and watch it come up
ssh "$MAC" '~/bin/tart-remote start-ide'
sleep 25
ssh "$MAC" '~/bin/tart-remote screenshot -' > ide.png

# 6. drive the GUI: click / type
ssh "$MAC" '~/bin/tart-remote click 800 450'
ssh "$MAC" '~/bin/tart-remote type "hello"'

# 7. record a short video of the GUI
ssh "$MAC" '~/bin/tart-remote record 15 -' > clip.mov

# 8. tear down
ssh "$MAC" '~/bin/tart-remote vm-down'        # stop (keep disk)  |  vm-gc to delete
```

![IntelliJ IDEA launched inside the VM and driven over SSH](docs/img/intellij-launched.png)

> *Above: `start-ide` launched IntelliJ IDEA CE (its EULA is on screen) and a
> `click` dismissed the Gatekeeper prompt — all over SSH from outside the Mac.*

## `tart-remote` command reference

```
Lifecycle (management "service"):
  vm-create            clone $TART_IMAGE into the VM (no-op if it exists)
  vm-up                configure + boot detached (survives SSH close) + wait for IP
  vm-ip                print the VM IP
  vm-status            exists / running / ip / provisioned
  vm-down              stop the VM (keeps the disk)
  vm-gc                stop + delete the VM
  provision            copy + run provision.sh in the guest

Drive the GUI:
  guest [cmd...]       run a command in the guest (interactive shell if none)
  screenshot [OUT]     capture the screen; OUT path on host, or '-'/omitted = PNG to stdout
  record SECS [OUT]    record SECS of video; OUT on host, or '-' = raw .mov to stdout
  start-ide [PROJECT]  launch IntelliJ (open PROJECT if given)
  click X Y            move + click at guest screen coords (cliclick)
  type TEXT            type into the focused field
  key KEYSTROKE        send a key/combo (e.g. cmd+space)
  pull :REMOTE LOCAL   copy a file out of the guest to the host
```

Configuration via environment (prefix on the remote side, keep consistent across calls):

| Env | Default | Meaning |
|---|---|---|
| `TART_VM` | `tart-skills-vm` | VM name |
| `TART_IMAGE` | `ghcr.io/cirruslabs/macos-tahoe-base:latest` | base image (macOS 26; `…-sequoia-base` = macOS 15) |
| `TART_CPU` | `4` | vCPUs |
| `TART_MEMORY` | `8192` | RAM (MiB) |
| `TART_DISPLAY` | `1600x900` | logical resolution (also the screenshot/video size) |
| `TART_USER` / `TART_PASS` | `admin` / `admin` | guest SSH credentials |
| `TART_DIR` | — | share a host dir into the guest: `name:/host/path[:ro]` |
| `TART_KEYCHAIN_PW` | — | Mac host user's **login** password; `vm-up` unlocks `login.keychain` with it (required for macOS guests on a headless macOS 15+ host — see notes) |

## How it works — design notes (all verified on real hardware)

- **Full GUI, headless host.** The VM boots `--no-graphics` (no window on the
  Mac), but Tart's base images auto-log-in `admin` into a complete Aqua session
  with `WindowServer`. `screencapture` and `cliclick` over SSH drive *that*
  session — which is exactly what GUI testing needs. To *watch* it live from a
  Mac: `tart run --vnc-experimental`.
- **Screen-recording grant.** An SSH session can't capture the screen until
  `kTCCServiceScreenCapture` is granted to `com.apple.sshd-session`. Tart's
  cirruslabs base images ship with SIP **off**, so `provision.sh` writes that
  grant directly into `TCC.db`. *(On macOS 15+/26 a periodic "bypass the private
  window picker" consent dialog also appears; captures still succeed, and the
  agent can clear the dialog with a `click` — see the screenshot skill.)*
- **Gatekeeper.** A cask-installed app is quarantined; the first `open` pops a
  "downloaded from the Internet" dialog. Provisioning strips
  `com.apple.quarantine` so `start-ide` opens straight into the IDE.
- **macOS guests need an unlocked login.keychain (macOS 15+).** Apple's
  Virtualization.framework refuses to boot a *macOS* guest if the host's
  `login.keychain` is locked, failing with a misleading `Code=-9` security
  error ("Failed to create new HostKey"). A headless SSH session leaves it
  locked. Set `TART_KEYCHAIN_PW` so `vm-up` runs `security unlock-keychain`
  first — or keep a GUI login session active on the host. Linux guests are
  unaffected. (See the [tart FAQ](https://tart.run/faq/) and
  [cirruslabs/tart#1146](https://github.com/cirruslabs/tart/issues/1146).)
- **`open -a`, not a bare launch.** A Java GUI app launched directly from an SSH
  shell dies with `HeadlessException`; `open -a` routes through launchd into the
  GUI session so windows render.
- **PATH.** A non-interactive SSH command sources only `~/.zshenv`, not
  `~/.zprofile` — so Homebrew's `/opt/homebrew/bin` (cliclick, ffmpeg) is off
  PATH by default. Provisioning adds brew to `~/.zshenv` and `tart-remote`
  prefixes a PATH export on every guest command.
- **stdout is data, stderr is logs.** `screenshot -`, `record N -`, and `vm-ip`
  emit clean bytes to stdout so you can redirect straight to a file.
- **No Homebrew required on the Mac.** `tart` installs as a standalone binary,
  and the inner-hop password auth uses `sshpass` *if present* or falls back to
  OpenSSH's `SSH_ASKPASS` (`SSH_ASKPASS_REQUIRE=force`, no tty needed) — so a
  bare macOS host with only Tart + stock `ssh` works.

Many of these lessons were distilled from a prior video-production project that
drove Tart VMs the hard way; this repo generalizes the durable ones into a
minimal, GUI-testing-focused toolkit.

## Testing

The Mac→VM layer here was validated end-to-end on real Apple Silicon: detached
boot, `tart ip`, screenshot (the images above are real captures), video capture,
IntelliJ install + launch, and cliclick — all over SSH. The outer Linux→Mac hop
is a thin SSH wrapper; test it against any reachable Apple Silicon Mac (or, for a
loopback smoke test, that same Mac's own `sshd`).

## License

[MIT](LICENSE) © 2026 Eugene Petrenko ([jonnyzzz](https://github.com/jonnyzzz))
