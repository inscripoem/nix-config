# Remote desktop on briefcase

Sunshine streams the SDDM login screen and the active desktop to Moonlight.
Capture runs through KMS (cap_sys_admin via a security wrapper), which
serves the pre-login greeter and any session compositor — niri and Plasma
Wayland alike. Tailscale provides remote connectivity.

## 1. Configuration

| Source | Responsibility |
|---|---|
| [Sunshine capability](../modules/nixos/capabilities/sunshine.nix) | System/user service handoff, polkit rule, firewall integration |
| [Display managers](../modules/nixos/desktop/display-managers.nix) | X11 SDDM greeter and default `niri` session |
| [WiFi profiles](../modules/nixos/capabilities/wifi-profiles.nix) | NetworkManager connections available before login |
| [Tailscale capability](../modules/nixos/capabilities/tailscale.nix) | Tailnet connectivity |

X11 was originally selected during NVIDIA/Wayland problems, when capture
ran over XShm and the greeter's X server was the only pre-login capture
target. With KMS capture the greeter backend no longer constrains capture;
the X11 SDDM greeter is retained as the known-good configuration.

## 2. Service handoff

1. SDDM starts its X server. System service `sunshine-sddm` runs as root, sets
   `DISPLAY=:0`, and reads the current `/run/sddm/xauth_*` cookie (unused by
   KMS capture, kept for the X11 capture fallback path).
2. Moonlight connects and displays the greeter. The user logs in through SDDM;
   PAM can unlock the desktop keyring normally.
3. The graphical session (niri, or Plasma Wayland) starts user service
   `sunshine`, running the cap_sys_admin security wrapper. Its
   `ExecStartPre` stops `sunshine-sddm`, then the user service takes over
   streaming and audio. Both services capture through KMS, so the handoff
   switches service ownership only, not the capture backend. (The removed
   `plasmax11` default used to share SDDM's X display so both services
   captured the same X server over XShm; that path died with the upstream
   Plasma X11 session removal.)
4. On logout, the user service's `ExecStopPost` starts `sunshine-sddm` again.

Both services use the same user's Sunshine configuration directory, sharing
pairing identity. Expect a short disconnect during handoff; previous sessions
measured about 5–8 seconds, but reconnect behavior depends on the client.
A polkit rule allows members of `users` to manage the specific system service.

`capSysAdmin` is enabled so both services share the KMS capture backend.
The X11 SDDM greeter is no longer a capture requirement; switching the
greeter backend is untested but no longer excluded by design.

## 3. Network and pairing

WiFi credentials are supplied by SOPS to NetworkManager system connections,
so the network does not wait for a user keyring unlock. See [secrets](secrets.md)
for the current fields and recipient setup.

After the user activates the configuration:

1. Confirm Ethernet or WiFi and Tailscale are available before login.
2. Open Sunshine's management UI at `https://HOST:47990` and set its credentials.
3. Add the host's Tailscale address in Moonlight and approve its pairing PIN
   through Sunshine's UI.
4. Connect to the greeter, log in, and reconnect after handoff if necessary.

Sunshine UI credentials manage the server; Moonlight uses pairing, and SDDM
still requires the operating-system login password.

`services.sunshine.openFirewall` manages the streaming ports. Port 47990 is
the HTTPS management UI, not the HTTPS streaming-control port at 47984.
Use the upstream module for the full port list rather than duplicating it here.

Sunshine settings are currently managed through its UI. Adding Nix
`services.sunshine.settings` changes the generated configuration path; review
both services' command lines and configuration ownership before doing so.

## 4. Troubleshooting and validation

At the greeter, inspect the system service; inside the desktop, inspect the
user service:

```sh
systemctl status sunshine-sddm
journalctl -b -u sunshine-sddm
systemctl --user status sunshine
journalctl --user -b -u sunshine
```

Check the XAUTHORITY file, display backend, port conflicts, and polkit handoff
if capture fails. Check NetworkManager/Tailscale separately if SSH is also
unreachable. Inspect Sunshine logs for the chosen hardware encoder.

After changing GPU, display manager, or capture mode, test the complete sequence:
boot → remote greeter → login → desktop/audio → logout → remote greeter.
Also test reconnect after reboot. Avoid assuming a desktop-only test covers it.

References: [Sunshine NixOS module](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/sunshine.nix),
[Sunshine boot autostart](https://app.lizardbyte.dev/2024-10-16-autostart-sunshine-on-boot-without-auto-login/).
