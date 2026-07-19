# XDG Desktop Portal on `briefcase`

Notes for the xdg-desktop-portal setup on this machine (KDE Plasma 6 on
Wayland, with niri and COSMIC as alternate Wayland sessions). These
explain **why** the portal config lives entirely at the system level
(`configuration.nix`) and **why** `home/desktop/plasma.nix` must not
touch `xdg.portal`, so the choice doesn't get "tidied" back into
trouble later.

Session: **KDE Plasma 6.5 / KWin Wayland**, SDDM Wayland greeter,
alternate sessions: **niri** (scrollable-tiling), **COSMIC**
Affected app that originally surfaced the problem: **Deskflow 1.25**
(Wayland client → needs `org.freedesktop.portal.RemoteDesktop` to
inject input via libei).

---

## 1. What xdg-desktop-portal is, in 30 seconds

`xdg-desktop-portal` is a D-Bus *router*. Sandboxed and unsandboxed apps
talk to a single well-known name (`org.freedesktop.portal.Desktop`) for
things like file pickers, screenshots, screencast, remote desktop, etc.
The router forwards each interface call to a **backend** of the form
`org.freedesktop.impl.portal.desktop.<name>` (e.g. `kde`, `gtk`,
`hyprland`, `wlr`, `gnome`).

A backend advertises which interfaces it implements via a `.portal` file
installed under `<datadir>/xdg-desktop-portal/portals/`. Routing rules
(which backend wins for which interface in which desktop) live in
`<configdir>/xdg-desktop-portal/<desktop>-portals.conf`.

Two things that bite you on NixOS:

1. **Not every backend implements every interface.** In particular
   `xdg-desktop-portal-gtk` does **not** implement `RemoteDesktop`. Only
   `xdg-desktop-portal-kde` (KWin/libei), `xdg-desktop-portal-gnome`
   (Mutter), and a few wlroots-side ones do.
2. **The portal router only scans the first `XDG_DATA_DIRS` entry that
   contains an `xdg-desktop-portal/portals/` subdirectory** and stops.
   This is the upstream behaviour (see
   <https://discourse.nixos.org/t/hyprland-home-manager-module-breaks-portal-discovery-for-other-desktop-environments/78042>).
   Put backends in two different prefixes and the second prefix becomes
   invisible.

---

## 2. Why portal config lives at the system level only

### The trap

Home-manager's `xdg.portal` module installs `.portal` files into
`/etc/profiles/per-user/<user>/share/xdg-desktop-portal/portals/`.
NixOS's system-level `xdg.portal` module installs them into
`/run/current-system/sw/share/xdg-desktop-portal/portals/`.

The per-user profile **appears earlier** in `XDG_DATA_DIRS` than the
system profile. Because the router stops at the first matching prefix
(see point 2 above), every system-level backend becomes effectively
unreachable as soon as home-manager declares *any* backend.

### What that looked like on this machine

We had:

```nix
# home/desktop/plasma.nix (REMOVED)
xdg.portal = {
  enable = true;
  extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
  ];
  config.common.default = [ "gtk" ];
};
```

with the system module pulling in `xdg-desktop-portal-kde` automatically
from `services.desktopManager.plasma6.enable`. Concrete symptom chain:

1. Deskflow client on Wayland called `org.freedesktop.portal.RemoteDesktop`.
2. The portal router only saw the per-user backends (gtk + wlr). Neither
   implements `RemoteDesktop`.
3. D-Bus returned
   `GDBus.Error:org.freedesktop.DBus.Error.InvalidArgs: No such interface "org.freedesktop.portal.RemoteDesktop"`.
4. `pgrep -af xdg-desktop-portal` showed `xdg-desktop-portal-gtk`
   running but **no** `xdg-desktop-portal-kde` process — confirming the
   KDE backend was never even reached for D-Bus activation.

### Decision

Manage `xdg.portal` **only** in `configuration.nix`. Remove the entire
block from `home/desktop/plasma.nix` and leave a comment there saying
why, so a later "consolidate user stuff in home-manager" refactor
doesn't reintroduce the bug.

`xdg-desktop-portal-wlr` was also dropped: it targets wlroots-based
compositors (Sway, Hyprland, ...). KWin is not wlroots, so the wlr
backend never does anything useful in a Plasma session — it just adds
noise to portal discovery.

---

## 3. The system-level config that works

```nix
# modules/nixos/desktop/xdg-portal.nix
xdg.portal = {
  enable = true;
  # niri does not register any portal backend itself; add gnome
  # explicitly so its session can route to it. plasma6 auto-adds the
  # kde portal and gtk is pulled in transitively, so they don't need
  # to be listed here.
  extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  # KDE session: route everything to the kde backend. It implements
  # RemoteDesktop (via KWin + libei), which is what deskflow needs on
  # Wayland. xdg-desktop-portal-gtk gets pulled in transitively but
  # must NOT win for RemoteDesktop because gtk lacks it.
  config.kde.default    = [ "kde" ];
  config.cosmic.default = [ "cosmic" ];
  # niri session: prefer the gnome backend (ScreenCast, RemoteDesktop,
  # Wallpaper, Background) with gtk as a fallback for the interfaces
  # gnome doesn't cover.
  config.niri.default   = [ "gnome" "gtk" ];
};
```

That's the entire system-level surface. `services.desktopManager.plasma6.enable`
already adds `xdg-desktop-portal-kde` to `xdg.portal.extraPortals`, and
`xdg-desktop-portal-gtk` gets pulled in transitively by GTK apps
(nautilus, evince, ...), so neither needs to be listed manually.
`xdg-desktop-portal-gnome` is different — nothing in the closure pulls
it in for us, so it has to be declared explicitly for the niri routing
above to actually resolve.

Resulting `extraPortals` on `briefcase` (sanity check via
`nix eval .#nixosConfigurations.briefcase.config.xdg.portal.extraPortals`):

- `xdg-desktop-portal-kde` (RemoteDesktop, ScreenCast, FileChooser, ...)
- `xdg-desktop-portal-gtk` (Settings, Print, AppChooser fallback, ...)
- `xdg-desktop-portal-gnome` (ScreenCast, RemoteDesktop, Wallpaper — for niri)
- `kwallet` (Secret — currently overridden, see `docs` on keyring)
- `gnome-keyring` (Secret)

Resulting `kde-portals.conf`:

```
[preferred]
default=kde
```

---

## 4. Verifying it after a rebuild

`nhs` alone does **not** restart the user-level portal processes — they
keep running from the previous nix-store path until the session ends.
After changing portal config you **must fully log out and log back in**
(or reboot) for the new backends to be picked up.

Once back in the session:

```fish
# Should now include xdg-desktop-portal-kde
pgrep -af xdg-desktop-portal

# Should list RemoteDesktop (and ScreenCast, Inhibit, ...) as
# advertised interfaces on the well-known portal object
gdbus introspect --session \
  --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop | grep -E 'interface (org\.freedesktop\.portal\.)'

# Confirm which .portal files the router actually loaded
G_MESSAGES_DEBUG=all systemctl --user restart xdg-desktop-portal
journalctl --user -u xdg-desktop-portal -n 50 | grep -i 'load'
```

First time a new app asks for RemoteDesktop, KDE pops a dialog
("Application X wants to remotely control this device"). Accept it,
optionally tick "remember", and from then on the app gets a persisted
session token.

---

## 5. Known-benign log noise to ignore

When debugging the *real* portal problem above, journal lines like:

```
Failed to register with host portal
QDBusError("org.freedesktop.portal.Error.Failed",
           "Could not register app ID:
            Connection already associated with an application ID")
```

look scary but are unrelated. This warning is emitted by many KDE
processes (`plasmashell`, `kded6`, `kaccess`, `ksecretd`,
`baloo_file_extractor`, ...) on every Plasma 6.x session and is tracked
upstream as a benign double-registration race. Do **not** chase this
warning when diagnosing portal interface availability; chase
`No such interface "org.freedesktop.portal.<X>"` instead.

---

## 6. Quick reference / when to revisit

| Question | Answer |
|---|---|
| Where does portal config live? | **`configuration.nix` only.** Never in home-manager. |
| Adding a new portal backend system-wide | `xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-foo ];` in `configuration.nix`, plus a routing entry under `xdg.portal.config.<desktop>` if you need to override defaults. |
| Switching desktop env later (e.g. add Hyprland) | Add `xdg-desktop-portal-hyprland` to system `extraPortals` and a `xdg.portal.config.hyprland` block. Still **don't** declare `xdg.portal` in home-manager. |
| Symptom: `No such interface "...RemoteDesktop"` again | First check `pgrep -af xdg-desktop-portal` for a `-kde` process; then check that `home-manager.users.<u>.xdg.portal.enable` is still `false` (someone may have re-added a per-user block). |
| Symptom: ScreenCast picker doesn't appear | Same checklist — same root cause class. |
