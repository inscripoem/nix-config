#!/usr/bin/env python3
"""Asar header-surgery patch: env-gate orca's boot-time window show.

Upstream shows the main window through one funnel:

    l=()=>{...c(),!t.Rn()&&(i&&n.maximize(),t.zn(n))}
    n.on(`ready-to-show`,l) + optional did-finish-load + 10s fallback timer

This script inserts `process.env.ORCA_SILENT_START||` in front of the
show segment, so an autostart launch with ORCA_SILENT_START=1 boots to
tray only: tray creation hooks the same ready-to-show event and is
independent of window visibility, and close-to-tray (see
orca-tray.py) keeps it resident afterwards. Every other entry point —
manual launch (gate unset), tray Open Orca/click, second-instance
restore — keeps its own show path untouched, and the gate short-
circuits without evaluating the rest of the expression.

Unlike pkgs/orca-tray.py this edit is not byte-length neutral (the
gate adds 31 bytes), so the archive is re-laid-out: every stored
file's bytes are kept verbatim, out/main/index.js grows by the gate,
all header offsets/sizes and the pickle framing are recomputed, and
"unpacked" entries (app.asar.unpacked natives) are left untouched.
Safe on Linux: Electron enforces embedded asar integrity only on
macOS/Windows, and this binary's EnableEmbeddedAsarIntegrityValidation
fuse is 0 anyway (decoded from the fuse wire, 2026-10-28).

Every step asserts; an llm-agents update that reshuffles bytes fails
the build loudly instead of silently skipping. In that case re-verify
ANCHOR against the new app.asar and adjust. Version bumps ride the
llm-agents flake input (see home/packs/ai.nix).
"""

import json
import struct
import sys

GATE = b"process.env.ORCA_SILENT_START||"
ANCHOR = b"c(),!t.Rn()&&(i&&n.maximize(),t.zn(n))"
PREFIX = b"c(),"
TARGET = "/out/main/index.js"


def fail(msg):
    sys.exit(f"orca silent-start patch: {msg}")


def main():
    asar = sys.argv[1]
    with open(asar, "rb") as fh:
        data = fh.read()

    if GATE in data:
        print("orca silent-start patch: already applied, nothing to do")
        return
    if data.count(ANCHOR) != 1:
        fail(f"anchor occurs {data.count(ANCHOR)} times, expected 1; refresh anchors")

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
    if not any(path == TARGET for path, _n, _c in entries):
        fail(f"{TARGET} not found in header")

    # Extract every stored file in archive order.
    recs = []
    for path, node, _chunk in entries:
        off = int(node["offset"])
        size = node["size"]
        if off + size > len(data):
            fail(f"{path} extends past archive end")
        recs.append([path, node, off, data[base + off : base + off + size]])
    recs.sort(key=lambda r: r[2])

    # Insert the gate into the target chunk (chunk-local anchor match).
    patched = False
    for rec in recs:
        path, node, off, chunk = rec
        if path != TARGET:
            continue
        if chunk.count(ANCHOR) != 1:
            fail(f"anchor occurs {chunk.count(ANCHOR)} times inside chunk, expected 1")
        at = chunk.find(ANCHOR) + len(PREFIX)
        rec[3] = chunk[:at] + GATE + chunk[at:]
        patched = True
    if not patched:
        fail("gate insertion never ran")

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
    print(
        f"orca silent-start patch: inserted {len(GATE)}-byte env gate into {TARGET} "
        f"(archive re-laid out, {len(data)} -> {len(blob)} bytes)"
    )


if __name__ == "__main__":
    main()
