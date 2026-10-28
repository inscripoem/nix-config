#!/usr/bin/env python3
"""In-place close-to-tray patch for the orca app.asar (Linux).

Upstream gates every piece of tray plumbing on win32/darwin, so the Linux
build quits outright on window close. This script flips four byte-length
neutral comparisons so Linux joins the win32 tray path:

  1. Tray creation gate (uf): platform!==`win32`&&platform!==`darwin`
     -> win32 becomes linux. On Linux the tray is then created through the
     exact code Windows uses (bundled icon + context menu Open Orca/Quit);
     the darwin branch (template icon, menubar extras) is not taken.
  2. Close-handler platform gate: same win32->linux swap, so the close
     event is allowed to consider hiding instead of quitting.
  3. The persisted-setting read in the close handler becomes a constant
     falsy term (short-circuited, so the setting is never even read).
     Upstream's first-run settings migration persists
     "minimizeToTrayOnClose":false into profile-state.db for every fresh
     profile (verified in the wild), so a default-flip alone never helps
     existing profiles; treating the stored value as advisory makes close
     always hide. Verified end-to-end on niri + DMS: tray registers on the
     session bus (libayatana-appindicator is already on the RUNPATH),
     close hides the window and keeps the daemon alive, and a second
     launch restores the window via the second-instance path.
  4. The tray click line keeps its win32 gate otherwise: the linux build
     would never set a tooltip nor attach the click handler, leaving the
     SNI item mute. Un-gating it to linux makes a single left-click on
     the DMS tray icon call Activate -> Electron's Tray click event ->
     onOpen, restoring the hidden window (verified by calling Activate
     over D-Bus on a hidden window). The tooltip text is "Orca"; note
     Electron's appindicator backend does not surface it as the SNI
     Title property, so hosts keep showing the cosmetic Id
     "Orca_status_icon_1".

Quit still works: the tray menu's Quit sets isQuitting first, and the
close handler short-circuits on getIsQuitting() before the hide branch.

The patch is byte-length neutral: every replacement preserves the asar
size, so all header offsets stay valid and the archive is fixed up in
place with no header surgery. Electron only enforces asar integrity
hashes on macOS/Windows (the EmbeddedAsarIntegrityValidation fuse is 0
in this binary), so no fuse handling is needed on Linux.

Every step asserts; an upstream update that reshuffles bytes fails the
build loudly instead of silently skipping. In that case re-verify the
anchors below against the new app.asar and adjust. Version bumps ride
the llm-agents flake input (see home/packs/ai.nix), so this check runs
on every flake update.
"""

import sys

PATCHES = [
    # (old, new): tray creation gate — create the tray on Linux too.
    (
        b"process.platform!==`win32`&&process.platform!==`darwin`)return null",
        b"process.platform!==`linux`&&process.platform!==`darwin`)return null",
    ),
    # Close-handler platform gate — let Linux reach the hide branch.
    (
        b"process.platform!==`win32`||n.isRendererProcessGone()",
        b"process.platform!==`linux`||n.isRendererProcessGone()",
    ),
    # Persisted-setting read — always falsy (see docstring point 3).
    (
        b"s?.getSettings().minimizeToTrayOnClose!==!0",
        b"!!0&&s?.getSettings().minimizeToTrayOnClose",
    ),
    # Tray click/tooltip line — attach click handler on Linux too, so a
    # left-click on the tray icon (SNI Activate) restores the window.
    # Semantically this removes tooltip+click from win32, which never runs
    # this Linux-only build; darwin takes the mCe() branch either way.
    (
        b"process.platform===`win32`?(Zd.setToolTip(rf())",
        b"process.platform===`linux`?(Zd.setToolTip(rf())",
    ),
]


def fail(msg):
    sys.exit(f"orca tray patch: {msg}")


def main():
    asar = sys.argv[1]
    with open(asar, "rb") as fh:
        data = fh.read()

    if PATCHES[0][1] in data:
        print("orca tray patch: already applied, nothing to do")
        return

    for old, new in PATCHES:
        if len(old) != len(new):
            fail(f"replacement for {old[:40]!r} is not byte-length neutral")
        n = data.count(old)
        if n != 1:
            fail(f"anchor {old[:48]!r} occurs {n} times, expected 1; refresh anchors")
        data = data.replace(old, new)

    with open(asar, "r+b") as fh:
        fh.write(data)
    print(f"orca tray patch: applied {len(PATCHES)} byte-length neutral edits to {asar}")


if __name__ == "__main__":
    main()
