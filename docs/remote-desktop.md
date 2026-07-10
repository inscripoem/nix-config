# Remote Desktop on `briefcase`

This machine is controllable remotely via **Sunshine + Moonlight** over
**Tailscale** with a **Windows-RDP-like experience**: boot the box,
Moonlight in, see the SDDM login screen, type the password, get the
desktop. No auto-login, no keyring unlocks without a password, nothing
left unlocked on the physical console.

The configuration is spread across:
- `modules/nixos/desktop/sunshine.nix` — the Sunshine host (root
  system service + user service handoff)
- `modules/nixos/desktop/display-managers.nix` — SDDM X11 greeter
- `modules/nixos/base/wifi.nix` — WiFi as a system connection (no
  KWallet dependency → boot-time network)
- `modules/nixos/tailscale.nix` — cross-region transport
- `secrets/wifi.yaml` (SOPS-encrypted) + `.sops.yaml` — WiFi PSK
- `docs/secrets.md` — SOPS/sops-nix framework

---

## 1. Tool selection (Wayland vs X11)

The NVIDIA proprietary driver (580.x on a Turing RTX 2060S; see
`docs/nvidia.md`) makes the `xdg-desktop-portal` screencast +
RemoteDesktop interfaces unstable under Wayland, and Wayland itself
also has the explicit-sync-first-frame-hang bug (`docs/nvidia.md` §3).
Every remote-desktop tool that goes through the portal (KRDP, krfb on
Wayland, RustDesk on Wayland, Deskflow on Wayland, ...) is therefore
unusable here. X11 avoids the portal entirely for screen capture —
tools read the framebuffer directly via XShm / XDamage — but the
Wayland-only tools (KRDP) disappear instead. For a single 1080p screen
with this NVIDIA card, X11 is the pragmatic choice.

| Tool | Protocol | Shares current screen | Wayland + NVIDIA | X11 + NVIDIA |
|------|----------|-----------------------|------------------|--------------|
| **KRDP** | RDP | yes | kcm shows up; relies on portal screencast + RemoteDesktop → NVIDIA portal unstable → **broken**. | **Wayland-only.** kcm metadata declares `X-KDE-OnlyShowOnQtPlatforms: ["wayland"]`; hidden on X11. |
| **krfb** | VNC (RFB) | yes | captures via portal screencast → NVIDIA portal unstable → **broken**. | works via XDamage, but pure CPU compression (Tight/ZRLE) — too laggy for cross-region use. |
| **RustDesk** | own | yes | Wayland path goes through portal + `uinput` → NVIDIA portal unstable → **flaky**. | works via `xcb_shm` capture + NVENC, **but** no NixOS host module; `--service` (unattended) needs sudo+setuid wrapper hack. |
| **Parsec** | own | yes | **No Linux host at all** (Windows/macOS only). | same — dead on arrival. |
| **xrdp** | RDP | no — opens a new Xorg session | not applicable; xrdp targets X. | usable for remote *login* to a fresh session, but does not shadow the active desktop. |
| **Sunshine** | Moonlight stream | yes | needs DRM/KMS capture (`capSysAdmin = true`); NVIDIA DRM has known GPU-ownership contention → **flaky**. | captures via XShm/XDamage (or NvFBC), **NVENC on Turing**, first-class NixOS module, no third-party account/signaling. **Chosen.** |

---

## 2. Architecture: Windows-RDP-like pre-login streaming

Instead of auto-login (which breaks KWallet/gnome-keyring because PAM
never sees a password → WiFi doesn't auto-connect, Vivaldi's cookie
store is lost), we use **two cooperating Sunshine processes**:

```
Boot → multi-user.target
  │
  ├─ NetworkManager (WiFi system-connection, auto-connects at boot)
  ├─ sshd.service (SSH available before any user logs in)
  │
  ├─ display-manager.service (SDDM)
  │   └─ X server on :0 (root, xauth at /run/sddm/xauth_*)
  │
  ├─ sunshine-sddm.service (ROOT, system, After=display-manager)
  │   └─ DISPLAY=:0, XAUTHORITY from /run/sddm/xauth_*
  │   └─ Moonlight connects → sees SDDM login screen
  │
  └─ [User types password via Moonlight → PAM → KDE session starts]
       └─ graphical-session.target reached
            └─ sunshine.service (USER, via NixOS module)
                 ├─ ExecStartPre: systemctl stop sunshine-sddm ← kill root service
                 └─ Moonlight reconnects → full desktop with PipeWire audio

  [User logout → sunshine.service stops]
       └─ ExecStopPost: systemctl start sunshine-sddm ← root takes over again
```

### Why this works

- SDDM starts an X server on `:0` before any user logs in. The root
  `sunshine-sddm` service sets `DISPLAY=:0` and dynamically finds SDDM's
  XAUTHORITY cookie at `/run/sddm/xauth_*` (root-readable). Sunshine
  grabs the greeter framebuffer via XShm/XDamage — no portal, no
  NVIDIA problem.
- No auto-login → no KWallet/keyring problem → PAM gets the password
  at real login → KWallet + gnome-keyring unlock properly → WiFi
  (already connected via system connection) doesn't need the keyring
  at all.
- The polkit rule in `sunshine.nix` lets the user service stop/start
  the system service without a password prompt.

### Handoff behaviour

When you type the SDDM password via Moonlight:
1. SDDM authenticates → starts `plasmax11` session
2. `graphical-session.target` reached → user `sunshine.service` triggers
3. `ExecStartPre` runs `systemctl stop sunshine-sddm` → root Sunshine
   exits → Moonlight disconnects (~1s)
4. User Sunshine starts (~5s) → phone a bit → Moonlight reconnects
   automatically → sees the logged-in desktop

Total moonlight downtime: **~5-8 seconds**. This is the best available
without auto-login.  The Sunshine pairing certificate is shared between
both services (root service sets `HOME=/home/inscripoem`), so Moonlight
sees a single host identity and reconnects to the same device UUID.

### Why root service, not auto-login

| | auto-login + lock (v4) | root system service (v5, current) |
|---|---|---|
| WiFi at boot | ❌ KWallet locked → no network → no SSH, no Moonlight | ✅ system connection → immediate |
| SSH before login | ❌ same reason | ✅ works |
| KWallet/gnome-keyring | ❌ locked (no password) → Vivaldi data loss | ✅ PAM unlock at real login |
| Remote sees | lock screen (same user already logged in) | SDDM login screen (can pick any user) |
| Moonlight drop | never | ~5-8s during handoff |
| Security | one user permanently logged in | no user logged in until remote auth |

---

## 3. WiFi as a system connection

The WiFi PSK is stored as a NetworkManager system connection (not in
KWallet) so the box has network at boot before anyone logs in. This is
how Windows stores WiFi profiles and is the only way to make SSH +
remote desktop available at boot on a WiFi-only machine.

The SSID and PSK live in `secrets/wifi.yaml` (SOPS-encrypted via the
host's SSH ed25519 key). At activation, `sops-nix` decrypts them to
`/run/secrets/WIFI_SSID` and `/run/secrets/WIFI_PSK`; a `sops.template`
builds a `wifi.env` environment file consumed by
`networking.networkmanager.ensureProfiles.environmentFiles` → `envsubst`
→ `.nmconnection` → `nmcli connection reload`.

See `modules/nixos/base/wifi.nix` for the implementation and
`docs/secrets.md` for the SOPS framework.

---

## 4. SDDM configuration

`modules/nixos/desktop/display-managers.nix`:

- `sddm.wayland.enable = false` — greeter must run on X11 so the root
  Sunshine service can grab the X server on `:0`.
- No `autoLogin` — we want the SDDM login screen to be what Moonlight
  sees.
- `defaultSession = "plasmax11"` — Plasma X11 session, the only
  xsessions entry on this box.

---

## 5. What the NixOS sunshine module already does

`services.sunshine.enable = true` in `sunshine.nix` pulls in, via the
upstream module:

- `hardware.uinput.enable = true` — kernel `uinput` module + perms
- `services.udev.packages = [ sunshine ]` — controller / udev rules
- `systemd.user.services.sunshine` — starts with `graphical-session.target`
- `services.avahi.publish.userServices = mkDefault true` — mDNS discovery
- `openFirewall = true` — the port table below

---

## 6. Port map

Base port `47989`; all others are offsets. Firewall opens are managed
by the sunshine module (`services.sunshine.openFirewall = true`). We
do NOT hand-list these in `networking.firewall`.

| Port  | Proto | Purpose |
|-------|-------|---------|
| 47984 | TCP   | HTTPS web UI (config + pair) |
| 47989 | TCP   | HTTP control / API |
| 47990 | TCP   | HTTP web UI (alt) |
| 48010 | TCP   | RTSP / control stream info |
| 47998 | UDP   | Video stream |
| 47999 | UDP   | Video stream |
| 48000 | UDP   | Control (encrypted) |
| 48002 | UDP   | Video stream |
| 48010 | UDP   | Control (encrypted) |

---

## 7. Usage

### One-time setup (after the first `nhs`)

1. Create the encrypted WiFi secret (see `docs/secrets.md` §7):
   ```bash
   sops secrets/wifi.yaml
   # Set WIFI_PSK to the actual password, save → sops encrypts automatically
   ```
2. `nhs` the first time. Reboot to verify WiFi auto-connects (see the
   SSID in `nmcli connection show --active`).
3. Pair Moonlight: on any Moonlight client on the same Tailnet, add a
   host using `briefcase`'s Tailscale IP. The root Sunshine service
   is already running and will show the SDDM login screen. Type the
   PIN, approve via Sunshine's web UI at `https://<tailnet-ip>:47990`.
4. Set the Sunshine username + password in the web UI (this is the
   Moonlight login credential).

### Daily use

1. Open Moonlight on any client, pick `briefcase`.
2. You see the SDDM login screen. Type the login password.
3. ~5-8s handoff → Moonlight reconnects → you're in the KDE desktop
   with NVENC + PipeWire audio.

### If the box reboots

WiFi auto-connects via system connection → sshd starts → Sunshine root
service starts → SDDM appears → Moonlight can connect. No human action
needed.

---

## 8. When to revisit

- **GPU swap to AMD** — X11 still works (Sunshine is backend-agnostic).
  On Wayland, Sunshine would need `capSysAdmin = true` for DRM/KMS
  capture. KRDP (RDP) also reappears as a non-streaming alternative.
  Either way, the sunshine-sddm root service + user service handoff
  architecture stays the same — only the capture mode changes.
- **Replace Moonlight with another client** — Sunshine speaks the
  standard Moonlight streaming protocol. Any Moonlight-compatible
  client (including built-in Moonlight clients on LG WebOS, Android
  TV, etc.) can connect. The remote desktop choice is **not locked**
  to Moonlight — it's locked to the Moonlight protocol, which is
  the Nvidia GameStream protocol openly reimplemented by Sunshine.
- **Replace Sunshine with another host** — the WiFi system connection
  and SSH are independent of the streaming host. Swapping Sunshine for
  e.g. a future RustDesk NixOS module or Wayland-stable KRDP does not
  touch anything else in this architecture.

---

## 9. Why `services.sunshine.settings` is left empty

`services.sunshine.settings` is intentionally not set. Setting any key
would force Sunshine to read exclusively from the generated `sunshine.conf`
and **disable the web UI**. Keeping it empty leaves the web UI at
`https://briefcase.local:47990` as the source of truth.

---

## 10. Sources

- Sunshine NixOS module: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/sunshine.nix
- LizardByte blog (autostart without auto-login): https://app.lizardbyte.dev/2024-10-16-autostart-sunshine-on-boot-without-auto-login/
- Revincx blog (Sunshine as root to capture SDDM): https://blog.revincx.icu/posts/sunshine-under-linux/index.html
- KRDP kcm Wayland-only commit: https://invent.kde.org/plasma/krdp/-/commit/2b699365
- xdg-desktop-portal-kde X11 refusal commit: https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/commit/29cb1d8
- Parsec Linux host unsupported: https://support.parsec.app/hc/en-us/articles/32381552552340
- NixOS SDDM module: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/display-managers/sddm.nix
- sops-nix: https://github.com/Mic92/sops-nix
- NetworkManager ensureProfiles: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/networkmanager.nix
- sops-nix + WiFi success case (Discourse): https://discourse.nixos.org/t/sops-nix-managing-wifi-ssid-psk-doesnt-allow-connection/60508