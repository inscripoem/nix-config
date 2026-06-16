# SDDM login broken by hardcoded WAYLAND_DISPLAY

A pitfall discovered in June 2026: hardcoding `WAYLAND_DISPLAY` in
`systemd.user.sessionVariables` breaks SDDM login on Wayland.

---

## Symptoms

1. SDDM greeter starts normally (Wayland or X11).
2. User enters password, authentication succeeds.
3. Session starts, then **immediately dies** — back to greeter, or
   black screen with cursor.
4. `journalctl` shows:

   ```
   kwin_wayland_drm: Atomic modeset test failed! Permission denied
   kwin_core: Applying output configuration failed!
   ```

   or (with Nouveau):

   ```
   kwin_wayland_drm: Modeset failed! Permission denied
   ```

5. Switching to X11 session (`plasmax11`) also fails — stuck loading
   screen, `plasmashell: QRhiGles2: Context is lost`.

The error looks like a DRM permission issue, but the real cause is
KWin choosing the wrong backend.

---

## Root cause

`WAYLAND_DISPLAY` was set in `systemd.user.sessionVariables`:

```nix
# WRONG — do NOT do this
systemd.user.sessionVariables = {
  DISPLAY = ":0";
  WAYLAND_DISPLAY = "wayland-0";
};
```

This injects `WAYLAND_DISPLAY=wayland-0` into **every** systemd user
session — including the SDDM greeter's session. KWin sees it, assumes
a Wayland compositor is running, and tries the Wayland backend instead
of DRM. No compositor exists → KWin crashes → session dies.

The `DISPLAY` and `WAYLAND_DISPLAY` variables are **runtime** values
set by the compositor at startup. Hardcoding them is always wrong —
the socket name (`wayland-0`) is not guaranteed.

---

## How to diagnose

```bash
# Check if WAYLAND_DISPLAY is leaking into the greeter session
journalctl -b --user -u sddm-helper-start-wayland | grep "backend"
```

If KWin says `automatically choosing Wayland because WAYLAND_DISPLAY
is set` during the greeter phase, the variable is leaking.

---

## The fix

Remove the hardcoded variables from `systemd.user.sessionVariables`.
The compositor (`startplasma-wayland`) sets `WAYLAND_DISPLAY` and
exports it to the systemd user environment via `systemd --user
import-environment` at session startup.

If KRunner-launched apps can't find `DISPLAY` / `WAYLAND_DISPLAY`
(a separate issue), use one of these instead:

1. **`systemd --user import-environment`** — run once after login, or
   add to a Plasma autostart script:

   ```bash
   systemd --user import-environment WAYLAND_DISPLAY DISPLAY
   ```

2. **`home.sessionVariables`** (home-manager) — writes to `~/.profile`,
   only sourced by login shells, does NOT pollute systemd user sessions:

   ```nix
   home.sessionVariables = {
     DISPLAY = ":0";
     WAYLAND_DISPLAY = "wayland-0";
   };
   ```

   Note: this also hardcodes the values, which is fragile. Prefer
   option 1.

---

## Key takeaway

`WAYLAND_DISPLAY` and `DISPLAY` are set by the compositor, not by
the system config. Never hardcode them in `systemd.user.sessionVariables`
— it will break SDDM and any other display manager that runs its
greeter as a systemd user session.
