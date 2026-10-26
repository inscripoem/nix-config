#!/usr/bin/env python3
"""In-place silent-start patch for the workbuddy app.asar.

Upstream shows the main window unconditionally once the renderer fires
ready-to-show (the window is created with show:false and only this call
ever maps it at boot). This script inserts an env gate in front of that
one show() call, so an autostart launch with WORKBUDDY_SILENT_START=1
stays in the tray; every other entry point (manual launch, tray click
via showOrCreate, deeplinks) keeps its own unconditional show:

    this.mainWindow?.show();
    ->  process.env.WORKBUDDY_SILENT_START||this.mainWindow?.show();

The patch is byte-length neutral: the 36-byte gate prefix is paid for by
removing a 36-byte char-aligned window from a JSDoc comment in the same
chunk, so every asar header offset stays valid and the archive is fixed
up in place with no header surgery. Electron only enforces asar
integrity hashes on macOS/Windows (the fuse is absent from this
binary), so the hashes need no update on Linux.

Every step asserts; an upstream update that reshuffles bytes fails the
build loudly instead of silently skipping. In that case re-verify the
anchors below against the new app.asar and adjust.
"""

import json
import struct
import sys

GATE = b"process.env.WORKBUDDY_SILENT_START||"
SHOW = b"this.mainWindow?.show();"
# Unique byte context pinning the boot-time show() inside its chunk.
ANCHOR = b"this.mainWindow?.maximize();\n\t\t\tthis.mainWindow?.show();"
# JSDoc line in the same chunk, positioned before ANCHOR; donates
# exactly len(GATE) bytes of comment text to keep the archive
# byte-length neutral.
DONOR = "负责首帧计时、traffic-light 位置、rendererReady 门禁与 pending 事件 flush。".encode()


def fail(msg):
    sys.exit(f"workbuddy silent-start patch: {msg}")


def main():
    asar = sys.argv[1]
    with open(asar, "rb") as fh:
        data = fh.read()

    if GATE + SHOW in data:
        print("workbuddy silent-start patch: already applied, nothing to do")
        return
    if data.count(ANCHOR) != 1:
        fail(f"show-call anchor occurs {data.count(ANCHOR)} times, expected 1; refresh anchors")
    site = data.find(ANCHOR) + len(ANCHOR) - len(SHOW)

    # Walk the asar header to find the file entry (chunk) holding `site`.
    # Layout: [0:4] pickle tag, [4:8] header pickle size, [8:12]/[12:16]
    # size echoes, [16:16+h3] header JSON; file data starts at 8+h1 and
    # entry offsets are relative to that.
    h1, _h2, h3 = struct.unpack("<III", data[4:16])
    base = 8 + h1
    header = json.loads(data[16 : 16 + h3])

    def locate(node):
        if "files" not in node:
            if node.get("unpacked"):
                return None
            start = base + int(node["offset"])
            return (start, start + node["size"]) if start <= site < start + node["size"] else None
        for child in node["files"].values():
            span = locate(child)
            if span:
                return span
        return None

    span = locate(header)
    if span is None:
        fail("show-call site maps to no archive file entry")
    start, end = span
    chunk = data[start:end]
    rel = site - start

    if chunk.count(SHOW) != 1:
        fail(f"show call occurs {chunk.count(SHOW)} times inside its chunk, expected 1")
    if chunk.count(DONOR) != 1:
        fail(f"donor comment occurs {chunk.count(DONOR)} times inside its chunk, expected 1")

    donor = chunk.find(DONOR)
    # First char-aligned window of exactly len(GATE) bytes inside the
    # donor comment, so the removal cannot split a UTF-8 sequence.
    sizes = [len(c.encode()) for c in DONOR.decode()]
    window = None
    acc = 0
    lo = 0
    for hi, size in enumerate(sizes):
        acc += size
        while acc > len(GATE):
            acc -= sizes[lo]
            lo += 1
        if acc == len(GATE):
            window = (
                donor + sum(sizes[:lo]),
                donor + sum(sizes[: hi + 1]),
            )
            break
    if window is None:
        fail("donor comment has no char-aligned window of len(GATE) bytes")
    w_lo, w_hi = window

    gate_at = rel
    if chunk[gate_at : gate_at + len(SHOW)] != SHOW or w_hi > gate_at:
        fail("donor window and show call site overlap or misordered; refresh anchors")
    patched = chunk[:w_lo] + chunk[w_hi:gate_at] + GATE + chunk[gate_at:]
    if len(patched) != len(chunk):
        fail("patched chunk length changed; byte-neutrality broken")
    if patched.count(GATE + SHOW) != 1:
        fail("patched chunk does not contain the gate exactly once")

    with open(asar, "r+b") as fh:
        fh.seek(start)
        fh.write(patched)
    print(
        f"workbuddy silent-start patch: gated show() at archive offset {site} "
        f"(chunk {start}..{end}, donated {w_hi - w_lo} comment bytes at {start + w_lo})"
    )


if __name__ == "__main__":
    main()
