# Enable GUI auto-login on the Mac host (startup action)

macOS guests need the host's `login.keychain` unlocked, or
Virtualization.framework refuses to boot them with a misleading `Code=-9`
security error (`Failed to create new HostKey`). A headless SSH session leaves
the keychain locked, so a freshly-rebooted Mac that nobody has logged into at
the console cannot boot a VM.

`TART_KEYCHAIN_PW` (see the [README notes](../README.md)) unlocks the keychain
per `vm-up`, which is enough for a one-off. For a **dedicated, always-on host**
the durable fix is to make the Mac **auto-login a real GUI user at every boot**.
That:

- unlocks `login.keychain` as part of the console login, so VM boots just work;
- gives the host a real Aqua/WindowServer session (also needed if you ever want
  to `screencapture` on the *host* itself, not just inside a VM);
- survives reboots with no per-session secret plumbing.

This is a **one-time host setup**, done over SSH.

## Prerequisites

- **FileVault must be OFF.** With FileVault on, macOS cannot auto-login (it needs
  the disk-unlock password at boot). Check:
  ```bash
  fdesetup status          # want: "FileVault is Off."
  ```
- You know the login password of the GUI user (here: `jetbrains`).

## Why not `sysadminctl -autologin`

Apple's supported command is:

```bash
sudo sysadminctl -autologin set -userName <user> -password <pw>
```

but on Apple Silicon it **fails over a headless SSH session** with
`SACSetAutoLoginPassword error:22` — it needs a Secure Token / GUI context it
doesn't have from a background SSH shell. So on a headless host you configure
auto-login the manual way: set `autoLoginUser` and write an XOR-obfuscated
`/etc/kcpassword` yourself. That is exactly what the supported command does
under the hood, and it is what the community `kcpassword` encoders do.

## Steps (over SSH)

1. **Point loginwindow at the auto-login user:**
   ```bash
   sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser jetbrains
   ```

2. **Write `/etc/kcpassword`.** macOS reads the login password from this file,
   XORed against a fixed 11-byte key. Encode it with the small script below
   (perl is always present on macOS; the stock `python3` may be just the Xcode
   stub). Keep the plaintext password out of process args — read it from a file:

   ```bash
   # on the Mac host; PWFILE holds the plaintext login password (no trailing newline needed)
   sudo perl - "$PWFILE" <<'PERL'
   use strict; use warnings;
   my $pw = do { local $/; open my $f, '<', $ARGV[0] or die $!; <$f> };
   $pw =~ s/[\r\n]+\z//;
   my @key = (0x7D,0x89,0x52,0x23,0xD2,0xBC,0xDD,0xEA,0xA3,0xB9,0x1F);
   my $k = @key;
   my @b = unpack 'C*', $pw;
   push @b, (0) x ($k - @b % $k) if @b % $k;          # pad up to a multiple of the key length
   for (my $n = 0; $n < @b; $n += $k) { $b[$n+$_] ^= $key[$_] for 0..$k-1 }
   open my $out, '>', '/etc/kcpassword' or die $!;
   binmode $out; print $out pack 'C*', @b; close $out;
   chmod 0600, '/etc/kcpassword'; chown 0, 0, '/etc/kcpassword';
   print "kcpassword written: ", scalar(@b), " bytes\n";
   PERL
   ```

3. **Reboot to activate** (auto-login only triggers at boot):
   ```bash
   sudo shutdown -r now
   ```

## Verify (after it comes back, ~30–90s)

The console must be owned by your user (not `root`/`loginwindow`) and a
WindowServer session must exist:

```bash
stat -f %Su /dev/console                 # want: jetbrains  (was: root)
scutil <<< 'show State:/Users/ConsoleUser' | grep -E 'Name|OnConsoleKey'
#   Name : jetbrains
#   kCGSSessionOnConsoleKey : TRUE
who                                       # want: jetbrains  console  ...
```

Then a VM boots without the `Code=-9` keychain error and `screenshot -` returns
a real desktop:

```bash
TART_VM=smoke ~/bin/tart-remote vm-up          # gets an IP in seconds, no Code=-9
TART_VM=smoke ~/bin/tart-remote screenshot - > shot.png
TART_VM=smoke ~/bin/tart-remote vm-gc
```

## Security note

`/etc/kcpassword` is reversible obfuscation, not encryption — anyone with root
on the host can recover the password. That is inherent to macOS auto-login. Use
it only on a **dedicated automation host** whose GUI user is low-privilege and
whose login password is not reused elsewhere. If you cannot accept a recoverable
on-disk password, use `TART_KEYCHAIN_PW` (kept in your secret store, passed per
`vm-up`) instead and leave the host at the login window.
