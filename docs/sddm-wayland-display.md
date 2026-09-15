# SDDM and display environment variables

Do not set a global `WAYLAND_DISPLAY` or `DISPLAY` for every user session.
The compositor supplies these values at runtime; greeter and desktop sessions
can use different sockets.

## Recorded failure

Hardcoded display variables in `systemd.user.sessionVariables` coincided with
successful SDDM authentication followed by a return to the greeter, a black
screen, or modeset errors such as:

```
kwin_wayland_drm: Atomic modeset test failed! Permission denied
```

An inherited `WAYLAND_DISPLAY` can make a compositor attempt a nested Wayland
backend instead of opening the intended DRM display. Modeset errors alone do
not establish this cause; inspect the startup environment and journal.

## Diagnosis and fix

Remove global hardcoded values, activate the configuration, and start a fresh
session. Inspect the affected session's environment and compositor log:

```sh
systemctl --user show-environment | rg '^(DISPLAY|WAYLAND_DISPLAY)='
journalctl -b -u display-manager
journalctl --user -b | rg -i 'kwin|backend|modeset'
```

The user-manager command describes the current account, not SDDM's separate
greeter account. Inspect the greeter's startup logs when the failure is there.

If an already running graphical session has correct shell variables but newly
launched services cannot see them, import those actual values:

```sh
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY
```

Run that from the graphical session whose environment should be imported.
Moving hardcoded values into `home.sessionVariables` does not solve the socket
selection problem.

A service explicitly targeting a known display may set a scoped value. The
[Sunshine greeter service](remote-desktop.md#2-service-handoff) deliberately
uses `DISPLAY=:0`; that is separate from setting it for all user sessions.
