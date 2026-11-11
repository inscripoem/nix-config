# Remote desktop on briefcase

Hermes streams the greeter login screen and the active desktop to
Moonlight / Artemis / Hestia. Both the pre-login greeter and the logged-in
user service use niri's direct `wlr-screencopy` path. This avoids an XDG
Portal screen-share approval that cannot be clicked on a headless output and
avoids the KMS DMA-BUF import failure observed as `EGL_BAD_MATCH (0x3009)`
on this host. Tailscale provides remote connectivity.

Hermes replaced Sunshine on 2026-11-11 after a pilot verified input, video
quality, and bidirectional text clipboard sync against the existing client
fleet. The swap was direct — the Sunshine capability module was deleted, not
kept behind a runtime switch — because `~/.config/sunshine` (old state) and
`~/.config/hermes` (current state) are independent directories and Hermes
seeds its pairing certificate from the Sunshine one on first start, so a
rollback is just `git revert` + `nhs switch`.

## 1. Configuration

| Source | Responsibility |
|---|---|
| [Hermes capability](../modules/nixos/capabilities/hermes.nix) | System/user service handoff, polkit rule, firewall ports, declarative settings (`capture`, `virtual_display_backend`), greeter wrapper, watchdog, uinput + udev rules, wl-clipboard for clipboard sync |
| [Hermes package](../pkgs/hermes/default.nix) | Upstream 0.7.0 source build; modeled on nixpkgs' sunshine derivation; updated by `scripts/update-versions.sh --only=hermes` |
| [Display managers](../modules/nixos/desktop/display-managers.nix) | greetd + Dux Greeter (niri greeter session) and default `niri` session |
| [WiFi profiles](../modules/nixos/capabilities/wifi-profiles.nix) | NetworkManager connections available before login |
| [Tailscale capability](../modules/nixos/capabilities/tailscale.nix) | Tailnet connectivity |

X11 was originally selected during NVIDIA/Wayland problems, when capture
ran over XShm and the greeter's X server was the only pre-login capture
target. With KMS capture the greeter backend no longer constrains capture,
and the X11 SDDM greeter has been replaced by greetd + Dux Greeter (the
DMS-native login screen inside a niri greeter session). See
`modules/nixos/desktop/display-managers.nix` for the session-enumeration
notes (XDG_DATA_DIRS via greetd's source_profile handling).

Why Hermes over the alternatives (host side): KRDP has no NixOS host path
and is Wayland-only; RustDesk has no NixOS *host* module (only the relay
server) and its unattended service needs a sudo+setuid wrapper under
NixOS; Parsec has no Linux host at all; krfb is CPU-only and too laggy for
HK<->SZ. Sunshine itself lost to its own fork lineage on the pilot's three
criteria: clipboard sync (Artemis control-stream extension, host side via
wl-copy/wl-paste), image quality at equal codec/bitrate (VBR with
single-frame VBV, zero-copy GBM/dmabuf capture), and the reference-client
roadmap (Artemis/Hestia).

## 2. Service handoff

1. greetd starts the Dux Greeter session on VT1 (a niri compositor running
   the greeter UI). System service `hermes-greeter` runs as root after
   `display-manager.service`, waits for the greeter user's Wayland socket
   (deadline 180 s), then waits until the compositor's IPC reports at
   least one output (niri binds its socket before the DRM scan finishes,
   and Hermes initializes its wlr capture once per process — starting
   against an output-less socket streamed "no display" until handoff,
   observed 2026-11-12), and captures the greeter through `capture=wlr`.
2. Artemis/Moonlight connects and displays the greeter. The user logs in
   through Dux Greeter; PAM (`greetd` service) can unlock the desktop
   keyring normally.
3. greetd starts the chosen graphical session (niri, or Plasma Wayland),
   which brings up user service `hermes`. Its `ExecStartPre` stops
   `hermes-greeter`, then the user service takes over streaming and
   audio.
4. On logout, the user service's `ExecStopPost` starts `hermes-greeter`
   again.

Both services use the same user's Hermes configuration directory, sharing
pairing identity and web-UI credentials. Expect a short disconnect during
handoff; reconnect behavior depends on the client. A polkit rule allows
members of `users` to manage the specific system service.

The greeter wrapper probes the first connected DRM connector (mirroring
niri's alphabetically-first placement of the greeter UI) and passes it as
`output_name`; an unmatched probe degrades to Hermes' first-monitor
default. The greeter unit sets `RestartPreventExitStatus = 1`: the wrapper
exits 1 when the greeter session has no Wayland socket (user-session
handoff/logout), and restarting that state every five seconds caused a
DRM/capture restart storm — the unit stays failed until the handoff
explicitly starts it again.

`virtual_display_backend = none` streams the session's own output; no EVDI
or Hermes-KMS driver is installed. Upstream's `--prelogin` pre-login
streaming is nightly-only and KDE+SDDM-tested; the handoff above stays
until it is proven for greetd+niri.

## 3. Clipboard sync

Text-only, bidirectional, through the Apollo control-stream extension
between Hermes and Artemis-family clients. The host side shells out to
`wl-copy` / `wl-paste` (wl-clipboard, installed system-wide by the
capability module); niri provides the wlr data-control protocol they talk
to. The 64 KiB cap and `text/plain` type mean images and file transfers do
not sync — copy text, or use a real file-transfer channel.

On the client side, clipboard sync requires an Artemis-family client:
Artemis (Android), Artemis Desktop (Windows/macOS/Linux, wjbeckett's
moonlight-qt fork), or Hestia (Linux). Generic Moonlight streams video,
audio, and input but has no Apollo extensions — no clipboard, no
permissions UI.

## 4. Client permissions (read this before "the stream is broken")

The FIRST client ever paired receives full permissions; every later
pairing defaults to View Streams + List Apps only — no mouse, keyboard,
launch, or clipboard permission. The symptom looks like a broken stream:
the picture freezes (no input → no desktop damage → damage-driven capture
emits no frames) and input is dead, while a full-permission client on the
same host works fine.

Fix per client: web UI (`https://HOST:47990`) → Clients → grant; or patch
the `perm` field in `~/.config/hermes/hermes_state.json` while Hermes is
stopped (the running process rewrites that file on exit). Full-permission
value used by this fleet's clients: `119480064`; a fresh pairing gets
`50331648`.

## 5. Network and pairing

WiFi credentials are supplied by SOPS to NetworkManager system connections,
so the network does not wait for a user keyring unlock. See [secrets](secrets.md)
for the current fields and recipient setup.

After the user activates the configuration:

1. Confirm Ethernet or WiFi and Tailscale are available before login.
2. Open Hermes' management UI at `https://HOST:47990` and set its
   credentials (first start migrated Sunshine's web-UI credentials).
3. Add the host's Tailscale address in the client and approve its pairing
   PIN through Hermes' UI.
4. Connect to the greeter, log in, and reconnect after handoff if
   necessary. Then check §4 — a freshly paired client is view-only.

Hermes UI credentials manage the server; clients use pairing, and the
greeter still requires the operating-system login password. Note the
greeter session has no fcitx5, so the password must be typeable on a plain
US keyboard layout.

Firewall ports (module-managed): TCP 47984 (HTTPS pairing/API), 47989
(HTTP/RTSP), 47990 (HTTPS web UI), 48010 (RTSP); UDP 47998/47999/48000
(video, control, audio). mDNS discovery rides the lan class's avahi
instance.

Settings are declarative (`hermesSettings` in the capability module); the
generated file is passed explicitly to both services. Review both command
lines after changing capture or output settings.

## 6. Troubleshooting and validation

**Startup hang**: either service can hang mid-init without exiting (port
47984 never binds), so `Restart=on-failure` never fires. A timer-driven
watchdog (`hermes-watchdog.timer`, every 2 min) restarts whichever
service — user or greeter — is active, portless, and older than 120 s.
Recovery is automatic within ~4 min; the journal line to look for is
`watchdog: ... hung portless past 120s, restarting`. Manual recovery:
`systemctl --user start hermes`. A service that is *inactive* is left
alone by design — auto-restarting cannot fix a broken unit; check the
unit file and the last evaluation instead. After the greeter wrapper
exits 1 (no Wayland socket), `hermes-greeter` stays *failed* by design
(`RestartPreventExitStatus = 1`) until the handoff starts it.

At the greeter, inspect the system service; inside the desktop, inspect
the user service:

```sh
systemctl status hermes-greeter
journalctl -b -u hermes-greeter
systemctl --user status hermes
journalctl --user -b -u hermes
```

Greeter-side problems go to `journalctl -b -u greetd` and, with
`logs.save` enabled, `/tmp/dms-greeter.log` (greeter compositor + UI).
Check the display backend, port conflicts, and polkit handoff if capture
fails. Check NetworkManager/Tailscale separately if SSH is also
unreachable. Hermes' own log lives at `~/.config/hermes/hermes.log`; the
encoder probe lines ("Trying encoder [nvenc]" → CUDA errors on this
AMD-only host) are expected noise. `GET /api/clipboard/status` reports
whether the clipboard helper is reachable.

After changing GPU, display manager, or capture mode, test the complete
sequence: boot → remote greeter → login → desktop/audio → logout → remote
greeter. Also test reconnect after reboot. Avoid assuming a desktop-only
test covers it.

References: [Hermes](https://github.com/MrOz59/Hermes),
[Hermes compatibility matrix](https://github.com/MrOz59/Hermes/blob/main/docs/compatibility.md),
[niri verified to adopt the Apollo-lineage virtual-display path](https://github.com/MrOz59/Hermes/blob/main/docs/compatibility.md)
(Hermes classifies niri as a wlroots compositor; wlr-output-management v4
matches niri's advertised version), [Artemis Desktop](https://github.com/wjbeckett/artemis).
