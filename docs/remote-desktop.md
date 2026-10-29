# Remote desktop on briefcase

Sunshine streams the greeter login screen and the active desktop to
Moonlight. Capture runs through KMS (cap_sys_admin via a security wrapper),
which serves the pre-login greeter and any session compositor — niri and
Plasma Wayland alike. Tailscale provides remote connectivity.

## 1. Configuration

| Source | Responsibility |
|---|---|
| [Sunshine capability](../modules/nixos/capabilities/sunshine.nix) | System/user service handoff, polkit rule, firewall integration |
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

## 2. Service handoff

1. greetd starts the Dux Greeter session on VT1 (a niri compositor running
   the greeter UI). System service `sunshine-greeter` runs as root after
   `display-manager.service` and captures the greeter through KMS.
2. Moonlight connects and displays the greeter. The user logs in through
   Dux Greeter; PAM (`greetd` service) can unlock the desktop keyring
   normally.
3. greetd starts the chosen graphical session (niri, or Plasma Wayland),
   which brings up user service `sunshine` with the cap_sys_admin security
   wrapper. Its `ExecStartPre` stops `sunshine-greeter`, then the user
   service takes over streaming and audio. Both services capture through
   KMS, so the handoff switches service ownership only, not the capture
   backend. (The removed `plasmax11` default used to share SDDM's X
   display so both services captured the same X server over XShm; that
   path died with the upstream Plasma X11 session removal.)
4. On logout, the user service's `ExecStopPost` starts `sunshine-greeter`
   again.

Both services use the same user's Sunshine configuration directory, sharing
pairing identity. Expect a short disconnect during handoff; previous sessions
measured about 5–8 seconds, but reconnect behavior depends on the client.
A polkit rule allows members of `users` to manage the specific system service.

`capSysAdmin` is enabled so both services share the KMS capture backend.

## 3. Fake streaming output (HDMI-A-1)

Streaming needs a lit CRTC: a GPU with nothing connected keeps no display
pipeline active, so a headless host has no framebuffer to capture at all.
Instead of a hardware dummy plug, the reserved port is force-enabled at
the DRM level and fed a generated EDID (`sunshine-fake-edid.bin`:
preferred 3840x2160@60 — the CEA-861 VIC 97 timing — plus a
1920x1080@60 standard timing) through the `video=` + `drm.edid_firmware`
kernel params. Every compositor and Sunshine see one constant "monitor",
so the streamed picture never drifts with whatever is plugged in on the
other ports.

**The fake port must be HDMI, not DisplayPort.** A forced DP connector
has no DPCD — there is no physical sink to report link capabilities —
so i915 validates every mode against the fallback link and only
640x480 survives (EDID load and parse are fine: the connector exposes
the injected EDID and its identity; the rejection happens at mode
validation). HDMI has no DPCD dependency. Verified live on the A380,
2026-10-28.

**The EDID must also carry a CEA-861 extension with an HDMI Forum
VSDB.** Without it the kernel never sets `display_info.max_tmds_clock`
and i915 caps the sink at the 165 MHz DVI baseline
(intel_hdmi.c `hdmi_port_clock_limit`): 1080p60 (148.5 MHz) survives
but 4K60 (594 MHz) is rejected — the generator's CEA extension block
(HDMI VSDB + HF-VSDB declaring a 600 MHz Max TMDS Character Rate,
SCDC deliberately not present since no sink answers I2C reads) lifts
the cap to the source's own limit. Both blocks are plain tag-3
vendor-specific blocks distinguished by OUI, not extended-tag blocks.

Port roles:

| Port | Role |
|---|---|
| DP-1..DP-3, HDMI-A-2 | real monitors (true EDID, native modes) |
| HDMI-A-1 | reserved fake output — never plug a real monitor in here; the forced EDID shadows it |

Routing by scenario:

| Scenario | Behavior |
|---|---|
| monitor present, local login | greeter UI on the real monitor (niri auto-placement: alphabetically-first connected output first) |
| monitor present, remote login | `sunshine-greeter` probes the first connected DRM connector and streams that output |
| headless, remote login | the fake output is the only one; the greeter runs on it at 1080p |
| logged in, remote desktop | user session pins the fake output at the same 1080p the real monitor runs; Sunshine's output selection must be `HDMI-A-1` |

The EDID binary is regenerated with
`modules/nixos/capabilities/sunshine-fake-edid.py` (validate with
`edid-decode`). The EDID keeps its 4K preferred timing as a dormant
option, but every consumer pins the fake output at 1080p — the same
mode the real monitor runs — so the desk screen and the streamed
picture are the same logical desktop. The greeter session has no idle
daemon, so nothing ever DPMS-blanks it — the pre-login stream stays
live indefinitely.

`fake-screen-toggle` is the session handover button between the two:

- **Going remote**: enables the fake output, then moves every workspace
  from the real monitor onto it — Moonlight picks up exactly what was
  on the desk screen.
- **Back at the desk**: disables the fake output; niri migrates its
  workspaces onto the remaining output automatically.

The toggle records its last state under
`~/.local/state/sunshine/fake-screen`; a session-start hook
(`fake-screen-init`, spawned by niri) restores "off" after a relogin,
since the config pin re-enables the output on every session start.

After changing GPU, re-verify the connector name — the
`modules.capabilities.sunshine.fakeOutputName` option is the single
source of truth; the kernel params, the greeter customConfig, the
wrapper probe and this document all derive from it, and the session
layer (home/desktop/niri.nix) reads it through `osConfig` while gating
on `sunshine.enable`, so non-streaming desktops carry no fake-output
config at all. The option has no default: it is host-specific physical
knowledge (which port the GPU enumerates free of monitors — and it must
be an HDMI port, per the note above), so every enabling host declares it
in its own config block — briefcase sets `HDMI-A-1` in
outputs/default.nix — and omitting it fails evaluation loudly. A second
streaming desktop needs the capability enabled plus its own
`fakeOutputName` line.

## 4. Network and pairing

WiFi credentials are supplied by SOPS to NetworkManager system connections,
so the network does not wait for a user keyring unlock. See [secrets](secrets.md)
for the current fields and recipient setup.

After the user activates the configuration:

1. Confirm Ethernet or WiFi and Tailscale are available before login.
2. Open Sunshine's management UI at `https://HOST:47990` and set its credentials.
3. Add the host's Tailscale address in Moonlight and approve its pairing PIN
   through Sunshine's UI.
4. Connect to the greeter, log in, and reconnect after handoff if necessary.

Sunshine UI credentials manage the server; Moonlight uses pairing, and the
greeter still requires the operating-system login password. Note the greeter
session has no fcitx5, so the password must be typeable on a plain US
keyboard layout.

`services.sunshine.openFirewall` manages the streaming ports. Port 47990 is
the HTTPS management UI, not the HTTPS streaming-control port at 47984.
Use the upstream module for the full port list rather than duplicating it here.

Sunshine settings are currently managed through its UI. Adding Nix
`services.sunshine.settings` changes the generated configuration path; review
both services' command lines and configuration ownership before doing so.

The user service captures whichever output Sunshine's UI has selected
(Configuration → Output Name). Set it to `DP-3` once for the 4K streaming
canvas; the greeter service does not use that setting — its wrapper probes
the first connected connector at every start. Switching the UI setting back
to a real monitor is how you stream the local screen from the desk instead.

## 5. Troubleshooting and validation

At the greeter, inspect the system service; inside the desktop, inspect the
user service:

```sh
systemctl status sunshine-greeter
journalctl -b -u sunshine-greeter
systemctl --user status sunshine
journalctl --user -b -u sunshine
```

Greeter-side problems go to `journalctl -b -u greetd` and, with
`logs.save` enabled, `/tmp/dms-greeter.log` (greeter compositor + UI).
Check the display backend, port conflicts, and polkit handoff if capture
fails. Check NetworkManager/Tailscale separately if SSH is also
unreachable. Inspect Sunshine logs for the chosen hardware encoder.

After changing GPU, display manager, or capture mode, test the complete sequence:
boot → remote greeter → login → desktop/audio → logout → remote greeter.
Also test reconnect after reboot. Avoid assuming a desktop-only test covers it.

The fake output adds its own matrix. `video=`/`drm.edid_firmware` are
boot-time params — a `nixos-rebuild switch` alone does not light DP-3 up;
reboot first. Then verify all four rows of the routing table above:
monitor-present local login, monitor-present remote greeter, headless
remote greeter (unplug + reboot or restart display-manager), and the
post-login 4K desktop stream. `cat /sys/class/drm/*/status` should show
DP-3 `connected` at all times; `niri msg outputs` shows DP-3 at
3840x2160 in the session.

References: [Sunshine NixOS module](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/sunshine.nix),
[Sunshine boot autostart](https://app.lizardbyte.dev/2024-10-16-autostart-sunshine-on-boot-without-auto-login/).
