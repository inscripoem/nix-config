# XDG desktop portals

Portal configuration belongs in the NixOS
[desktop module](../modules/nixos/desktop/xdg-portal.nix), not a second
Home Manager portal configuration. This keeps backend discovery and routing
in one profile.

## Why one owner

The original Deskflow failure in a Plasma Wayland session was:

```
No such interface "org.freedesktop.portal.RemoteDesktop"
```

HM had installed GTK/wlr portal definitions in a per-user prefix ahead of the
system KDE backend. The portal router's discovery order hid the required
backend. GTK does not implement RemoteDesktop, so changing a default to GTK
could not solve the missing interface.

That failure was observed on the previous Wayland setup. The current default
session on `briefcase` is Plasma X11; niri and COSMIC remain available.
Interface availability depends on the running desktop and backend support.

### Discovery and routing

Applications call the D-Bus service `org.freedesktop.portal.Desktop`. The portal
router forwards each supported interface to a desktop backend. Two file types
control different parts of this process:

- `share/xdg-desktop-portal/portals/*.portal` advertises a backend's interfaces
  and D-Bus service name.
- `xdg-desktop-portal/<desktop>-portals.conf` selects preferred backends for
  the session and individual interfaces.

In the recorded failure, discovery used the first matching portal directory in
`XDG_DATA_DIRS`. HM's `/etc/profiles/per-user/<user>/share` preceded the system's
`/run/current-system/sw/share`, so installing only GTK/wlr there hid the KDE
definition later in the search path. A routing preference cannot select a
backend the router has not discovered. Keeping installation at the system
layer ensures the required definitions are collected in one profile.

## Routing

| Session | Default | Interface overrides |
|---|---|---|
| KDE | `kde` | None in this module |
| COSMIC | `cosmic` | None in this module |
| niri | `gnome`, then `gtk` | Access/Notification → GTK; Secret → GNOME Keyring |

The module explicitly adds the GNOME backend for niri. Desktop modules provide
other backends. niri's Access/Notification overrides avoid relying on an absent
GNOME Shell. A routing entry alone does not guarantee the compositor implements
the required protocol.

When adding a desktop, install its backend and routing at the system layer.
Check the effective backend list instead of copying an old package inventory.

## Verification

After changing portal configuration and activating, log out and back in to
replace user processes and their environment. In the affected session:

```sh
printf '%s\n' "$XDG_CURRENT_DESKTOP" "$XDG_DATA_DIRS"
pgrep -af xdg-desktop-portal
gdbus introspect --session \
  --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop
journalctl --user -b -u xdg-desktop-portal
```

For a missing interface, inspect the selected backend, its advertised
interfaces, and earlier per-user portal directories. A backend process may
start only when requested; its absence before a request is not conclusive.
Finally test the actual file picker, screen share, or remote-input operation.

On the configured NixOS host, these paths help distinguish missing definitions
from incorrect preferences:

```sh
ls /run/current-system/sw/share/xdg-desktop-portal/portals/
ls "/etc/profiles/per-user/$USER/share/xdg-desktop-portal/portals/"
ls /etc/xdg/xdg-desktop-portal/
```

An absent per-user portal directory is expected in this setup. Also inspect any
user configuration under `~/.config/xdg-desktop-portal/` that could override
system preferences. Compare the requested interface with the selected
backend's `.portal` file, then read the router journal from the same session.

Reference: [NixOS portal discovery discussion](https://discourse.nixos.org/t/hyprland-home-manager-module-breaks-portal-discovery-for-other-desktop-environments/78042).
