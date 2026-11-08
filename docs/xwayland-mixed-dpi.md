# Mixed-DPI X11 scaling under niri

Status: shelved 2026-11-08. briefcase is back on a single 1080p output at
niri scale 1, where the problem does not appear. The Steam wrapper stays in
place; on that output it writes scale 1.0 and has no other effect. Revisit
when a 4K or mixed-DPI output is used again.

## Symptom and environment

On 2026-11-04 Steam's UI text on the Sunshine virtual 4K output was half the
size of Wayland applications. The session had:

- a real 1080p output at niri scale 1 (DP-3 on that date, DP-4 after the
  monitor change);
- the Sunshine fake 4K output `HDMI-A-1` at niri scale 2 (3840x2160 physical,
  1920x1080 logical);
- xwayland-satellite 0.8.3, niri-unstable 2026-10-31, and Steam client
  1.0.0.87 (build 1792618285).

Evidence collected at the time:

- Xwayland's screen was 5760x2160 physical with `Xft.dpi: 96`.
- `logs/webhelper_gpu.txt` reported `Display[...] 3840x2160 scale=1` and
  `Display[...] 1920x1080 scale=1`: Steam saw no HiDPI scale on either output.
- The Steam webhelper rendered a 2018x1913 CSS viewport into a 1010x1028
  logical niri tile. That is 1 CSS pixel per physical pixel, while Wayland
  clients draw 1 logical pixel as 2 physical pixels on a scale-2 output.

## Root cause

xwayland-satellite runs one Xwayland at the smallest scale among the enabled
outputs. X11 clients do not receive the compositor's per-output scale, and
satellite maps their pixels 1:1 to the output's physical pixels. Steam is an
X11/CEF client and renders its UI at 1x, so on a scale-2 output it occupies
half the intended size. Any X11 client that does not scale itself has the
same problem (Steam, Wine, Electron without Ozone Wayland).

Upstream position:

- [xwayland-satellite #180](https://github.com/Supreeeme/xwayland-satellite/issues/180):
  the maintainer calls the smallest-DPI behaviour intentional and recommends
  per-application scale variables (`GDK_SCALE`, `GDK_DPI_SCALE`,
  `QT_SCREEN_SCALE_FACTORS`); the request was closed as not planned.
- [niri #3613](https://github.com/niri-wm/niri/discussions/3613): niri
  delegates Xwayland entirely to satellite and has no per-output Xwayland
  scale option.

## What did not work

| Mechanism | Result |
|---|---|
| `STEAM_FORCE_DESKTOPUI_SCALING=2.0` | Present in the Steam process environment; the client did not pass `--force-device-scale-factor` to `steamwebhelper`. |
| `steam -forcedesktopscaling 2` | Reached the client command line; no effect. |
| `steam --force-device-scale-factor=2` | Reached the client; not forwarded to the UI process. |
| `xrdb -merge` with `Xft.dpi: 192` | No effect; the webhelper still reported display scale 1. |
| Settings > Interface > "Scale text and icons to match monitor settings" | Already checked; auto-detection sees X11 scale 1, so it produces 1.0. |

The documented environment variable and command-line switches are therefore
inert in this client build.

## Working Steam fix

The knob that works is Steam's own Accessibility display scale, persisted as
`Accessibility/DesktopUIScale` in
`~/.local/share/Steam/config/config.vdf` (the Settings > Accessibility
slider). The client reads it at startup. Writing `2` while Steam is stopped
produces, in `logs/webhelper.txt`:

```
ThreadSetForceDeviceScaleFactors 1.000000 * 2.000000 = 2.000000
```

Implementation: [gaming.nix](../modules/nixos/capabilities/gaming.nix)
(`programs.steam.package = pkgs.steam.override { extraPreBwrapCmds = ...; }`).
On a fresh Steam launch in a niri session it:

1. skips if a Steam client is already running (second launches are URL
   forwards);
2. reads the focused output's scale with `niri msg --json focused-output`;
3. clamps it to Steam's supported 0.5-2.0 range;
4. atomically rewrites `DesktopUIScale` in `config.vdf` when the key exists
   and the value differs.

Commits: `3457af4` first tried the environment variable (dead); `2fd6c61`
replaced it with the configuration rewrite. Plasma is untouched: the block
is gated on `XDG_CURRENT_DESKTOP` containing `niri`, because KWin scales
Xwayland itself.

Limits:

- Steam cannot rescale a running client; moving the window between outputs of
  different scales requires a Steam restart.
- The wrapper owns the Accessibility slider in niri sessions; manual changes
  are overwritten on the next launch.
- The slider's maximum is 2.0, so an output scaled above 2.0 cannot be
  matched.
- The scale is chosen from the focused output at launch; if Steam opens on a
  different output, restart it there.
- Only the standard `~/.local/share/Steam` layout is handled.
- The value lives in local Steam configuration. Whether the account syncs it
  to other machines was not verified.

Operational note: at shelving time `config.vdf` still contained `2` from the
4K tests. The next fresh launch on the 1080p output rewrites it to `1.0`
before the client starts.

## Other X11 clients

WorkBuddy ([workbuddy.nix](../pkgs/workbuddy.nix), Electron 35) is an X11
client: its main process has a connection to `@/tmp/.X11-unix/X0`, and the
launcher passes no Ozone/Wayland flags. On the 1080p output it is normal. On
a scale-2 output it would render small like Steam. Two options if 4K
returns:

1. run it natively on Wayland with `--ozone-platform=wayland` or
   `ELECTRON_OZONE_PLATFORM_HINT=auto`, then verify tray, IME, and screen
   capture;
2. add a launch-time wrapper that passes
   `--force-device-scale-factor=<focused output scale>`, with the same
   restart-on-move limitation as Steam.

Neither was implemented.

## Upstream PR #452

[xwayland-satellite PR #452](https://github.com/Supreeeme/xwayland-satellite/pull/452)
adds compositor-side supersampling for mixed DPI: X11 applications render at
the largest output scale, and the compositor downscales them on lower-DPI
outputs through `wp_viewport`. It is opt-in with
`XWAYLAND_SATELLITE_COMPOSITOR_SCALING` and accepts
`XWAYLAND_SATELLITE_BASE_SCALE` (1.0-8.0). The same PR also adds EWMH
maximization, input-region scaling, and clipboard hardening.

Status as of 2026-11-08: open, unmerged, and conflicting with main
(`mergeable: CONFLICTING`). The branch is based on `324ef5d`, three commits
behind its declared base `b83eab9`, and lacks upstream focus/viewport fixes.
The maintainer's review asked for the behaviour to be default-on and doubted
cross-application correctness; he has not approved it.

A static security review of the PR (2026-11-04, no build or execution) found
no malicious code: no network or telemetry, process execution, persistence,
sensitive file access, obfuscation, new `unsafe`, or dependency/build
changes; the three commits carry the author's SSH signature. It did identify
non-malicious risks:

- pending clipboard transfers have no total limit, allowing local fd/memory
  exhaustion;
- every popup's input region is cleared, not only override-redirect popups;
- `RegionOp` accumulation and full clones on each `SetInputRegion` allow
  memory/CPU growth from X11 clients;
- the 16 MB clipboard cap breaks larger INCR transfers and applies in one
  direction only;
- tests mutate `XWAYLAND_SATELLITE_BASE_SCALE` globally and can race;
- `steam`/`steamwebhelper` WM_CLASS gets a special window-role case unrelated
  to the stated feature;
- startup calls `update_global_scale(1.0)`, briefly resetting `Xft.dpi` to 96.

The PR is not adopted.

## If 4K or mixed DPI returns

1. Confirm the installed wrapper is current (`nhs`), launch Steam on the
   target output, and check `logs/webhelper.txt` for
   `ThreadSetForceDeviceScaleFactors ... = <scale>`.
2. Decide whether WorkBuddy should run native Wayland or use a dynamic scale
   flag.
3. Re-check PR #452. If merged, upgrade xwayland-satellite, evaluate the
   supersampling mode, and consider deleting the Steam-specific wrapper.

## References

- [ArchWiki HiDPI, Steam section](https://wiki.archlinux.org/title/HiDPI#Steam)
- [xwayland-satellite README, Scaling/HiDPI](https://github.com/Supreeeme/xwayland-satellite#scalinghidpi)
- [xwayland-satellite issue #180](https://github.com/Supreeeme/xwayland-satellite/issues/180)
- [niri discussion #3613](https://github.com/niri-wm/niri/discussions/3613)
- [xwayland-satellite PR #452](https://github.com/Supreeeme/xwayland-satellite/pull/452)
