#!/usr/bin/env python3
r"""Regex-based asar patcher for orca (Linux), five semantic edits.

Upstream gates every piece of tray plumbing on win32/darwin, so the Linux
build quits outright on window close, and there is no headless/silent
boot path. This script makes five edits to app.asar:

  1. Tray creation gate (platform!==`win32`&&platform!==`darwin`
     -> win32 becomes linux). On Linux the tray is then created through
     the exact code Windows uses (bundled icon + context menu Open
     Orca/Quit); the darwin branch (template icon, menubar extras) is
     not taken.
  2. Close-handler platform gate: same win32->linux swap, so the close
     event is allowed to consider hiding instead of quitting.
  3. The persisted-setting read in the close handler becomes a constant
     falsy term (short-circuited, so the setting is never even read).
     Upstream's first-run settings migration persists
     "minimizeToTrayOnClose":false into profile-state.db for every fresh
     profile (verified in the wild), so a default-flip alone never helps
     existing profiles; treating the stored value as advisory makes
     close always hide.
  4. The tray click/tooltip line keeps its win32 gate otherwise: the
     linux build would never set a tooltip nor attach the click
     handler, leaving the SNI item mute. Un-gating it to linux makes a
     single left-click on the DMS tray icon call Activate -> Electron's
     Tray click event -> onOpen, restoring the hidden window. The
     tooltip text is "Orca"; note Electron's appindicator backend does
     not surface it as the SNI Title property, so hosts keep showing
     the cosmetic Id "Orca_status_icon_1".
  5. Boot-time show funnel (the ready-to-show handler
     `...!X.Y()&&(a&&w.maximize(),X.Z(w))`): inserts
     `process.env.ORCA_SILENT_START||` in front of it, so an autostart
     launch with ORCA_SILENT_START=1 boots to tray only (tray creation
     hooks the same ready-to-show event and is independent of window
     visibility; close-to-tray above keeps it resident). Every other
     entry point — manual launch (gate unset), tray Open Orca/click,
     second-instance restore — keeps its own show path untouched.

Quit still works: the tray menu's Quit sets isQuitting first, and the
close handler short-circuits on getIsQuitting() before the hide branch.

Tolerance design: orca releases ship minified bundles whose identifiers
are reshuffled on every version bump, so anchors hard-coding names
(gf.setToolTip(Sf())) broke at 1.4.245. Every pattern here pins only
semantically stable scaffolding (process.platform comparisons, setting
names, call shapes) and wildcards the minified identifiers with \w+.
What still breaks the build: upstream refactoring one of the five sites
themselves — which fails loudly with a context dump rather than
silently shipping a close-quits-on-Linux regression.

The archive is re-laid out after patching (every stored file's bytes
kept verbatim, all header offsets/sizes and the pickle framing
recomputed, "unpacked" entries untouched), so replacements may change
length. Electron only enforces asar integrity hashes on macOS/Windows
(the EmbeddedAsarIntegrityValidation fuse is 0 in this binary), so no
fuse handling is needed on Linux.

Version bumps ride the llm-agents flake input (see home/packs/ai/orca.nix);
there is no update-versions.sh section (same exemption class as the
workbuddy autostart twin).
"""

import json
import re
import struct
import sys

GATE = b"process.env.ORCA_SILENT_START||"

# Minified identifiers may start with "$": 1.4.246 renamed the tray
# tooltip helper to `$i`, which \w does not match.
ID = rb"[\w$]+"

# (name, pattern, replacement): replacement is a function over the match
# bytes. win32->linux swaps are byte-length neutral; the P3/P5 edits are
# not, which is fine under the re-layout below.
PATCHES = [
    (
        "tray-creation-gate",
        rb"process\.platform!==`win32`&&process\.platform!==`darwin`\)return null",
        lambda m: m.group(0).replace(b"win32", b"linux"),
    ),
    (
        "close-handler-platform-gate",
        rb"process\.platform!==`win32`\|\|(" + ID + rb")\.isRendererProcessGone\(\)",
        lambda m: m.group(0).replace(b"win32", b"linux"),
    ),
    (
        "close-handler-setting-read",
        rb"(" + ID + rb")\?\.getSettings\(\)\.minimizeToTrayOnClose!==!0",
        lambda m: b"!!0&&" + m.group(0)[: -len(b"!==!0")],
    ),
    (
        "tray-click-tooltip-gate",
        rb"process\.platform===`win32`\?\(" + ID + rb"\.setToolTip\(" + ID + rb"\(\)\)",
        lambda m: m.group(0).replace(b"win32", b"linux"),
    ),
    (
        "boot-show-silent-gate",
        rb"!" + ID + rb"\." + ID + rb"\(\)&&\(" + ID + rb"&&" + ID
        + rb"\.maximize\(\)," + ID + rb"\." + ID + rb"\(" + ID + rb"\)\)",
        lambda m: GATE + m.group(0),
    ),
]


def fail(msg):
    sys.exit(f"orca patch: {msg}")


def main():
    asar = sys.argv[1]
    with open(asar, "rb") as fh:
        data = fh.read()

    if GATE in data:
        print("orca patch: already applied, nothing to do")
        return

    # Frame layout: [0:4] pickle tag (4), [4:8] h1, [8:12] h2, [12:16] h3
    # = header JSON byte length; JSON at [16:16+h3]; data section starts
    # at base = 8 + h1 and entry offsets are relative to base. Chromium
    # pickle pads the payload to a 4-byte boundary.
    h1, h2, h3 = struct.unpack("<III", data[4:16])
    base = 8 + h1
    pad = (-h3) % 4
    if not (h1 == h2 + 4 and h2 == 4 + h3 + pad and base == 16 + h3 + pad):
        fail(f"unexpected pickle framing h1={h1} h2={h2} h3={h3}")
    header = json.loads(data[16 : 16 + h3])

    entries = []

    def walk(node, path):
        if "files" in node:
            for name, child in node["files"].items():
                walk(child, f"{path}/{name}")
            return
        if node.get("unpacked"):
            return
        entries.append([path, node, None])

    walk(header, "")
    if not entries:
        fail("asar header contains no stored entries")

    # Extract every stored file in archive order.
    recs = []
    for path, node, _chunk in entries:
        off = int(node["offset"])
        size = node["size"]
        if off + size > len(data):
            fail(f"{path} extends past archive end")
        recs.append([path, node, off, data[base + off : base + off + size]])
    recs.sort(key=lambda r: r[2])

    # Locate each pattern across the whole archive first: every patch must
    # match exactly one stored byte range, so a future reshuffle that moves
    # or duplicates a site fails loudly with its context instead of
    # silently skipping or corrupting a second match.
    for name, pattern, repl in PATCHES:
        hits = []
        for rec in recs:
            for m in re.finditer(pattern, rec[3]):
                hits.append((rec, m))
        if len(hits) != 1:
            contexts = [
                data[base + r[2] + m.start() - 40 : base + r[2] + m.end() + 40]
                for r, m in hits[:3]
            ]
            fail(
                f"{name}: pattern matched {len(hits)} times across the archive, "
                f"expected 1; refresh the anchor. Contexts: {contexts!r}"
            )
        rec, m = hits[0]
        chunk = rec[3]
        rec[3] = chunk[: m.start()] + repl(m) + chunk[m.end() :]

    # Re-layout: sequential offsets, sizes updated in place (assignment
    # keeps each key's original position, so upstream JSON key order is
    # preserved).
    out = bytearray()
    cur = 0
    for path, node, _off, chunk in recs:
        node["offset"] = str(cur)
        node["size"] = len(chunk)
        out += chunk
        cur += len(chunk)

    new_json = json.dumps(header, separators=(",", ":")).encode()
    new_pad = (-len(new_json)) % 4
    new_h2 = 4 + len(new_json) + new_pad
    new_h1 = new_h2 + 4
    blob = (
        struct.pack("<IIII", 4, new_h1, new_h2, len(new_json))
        + new_json
        + b"\0" * new_pad
        + bytes(out)
    )

    # Roundtrip: the rebuilt frame must parse back to the same content.
    rb1, rb2, rb3 = struct.unpack("<III", blob[4:16])
    if not (rb1 == new_h1 and rb2 == new_h2 and rb3 == len(new_json)):
        fail("rebuilt frame does not roundtrip")
    if json.loads(blob[16 : 16 + rb3]) != header:
        fail("rebuilt header does not roundtrip")
    if blob.count(GATE) != 1:
        fail("gate missing after re-layout")

    with open(asar, "wb") as fh:
        fh.write(blob)
    applied = ", ".join(name for name, _p, _r in PATCHES)
    print(
        f"orca patch: applied {applied} to {asar} "
        f"(archive re-laid out, {len(data)} -> {len(blob)} bytes)"
    )


if __name__ == "__main__":
    main()
