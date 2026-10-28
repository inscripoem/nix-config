#!/usr/bin/env python3
"""Generate the fake-monitor EDID binary used by the briefcase Sunshine
capability (modules/nixos/capabilities/sunshine.nix).

The binary is committed; regenerate and revalidate with:

    python3 dp3-fake-edid.py > dp3-fake-edid.bin
    edid-decode dp3-fake-edid.bin

Structure (EDID 1.4, 128 bytes, no extensions):
  - Preferred detailed timing: 3840x2160@60, the CEA-861 VIC 97 timing
    (594.000 MHz pclk, hblank 560 = 176+88+296, vblank 90 = 8+10+72).
    This is the mode niri pins for the streaming canvas.
  - Standard timing slot 1: 1920x1080@60 (aspect code 11 = 16:9; the
    kernel's std timing parser never adopted the EDID 1.4 redefinition).
    SDDM's Xsetup switches the fake output to this mode when headless so
    the greeter stays readable and stream-friendly.
  - Range limits descriptor covers both modes (H 66-137 kHz, V 58-62 Hz,
    max pclk 600 MHz) so DRM does not filter the 1080p standard timing.
"""

import sys

BYTEMAP = []


def emit(offset, comment, *values):
    BYTEMAP.extend(values)
    print(f"  {offset:#06x}: {' '.join(f'{v:02X}' for v in values)}  ; {comment}", file=sys.stderr)


def dtd(pclk_khz, hact, hfp, hs, hbp, vact, vfp, vs, vbp, hmm, vmm, flags=0x1E):
    """18-byte detailed timing descriptor, layout per E-EDID (matches the
    kernel's struct detailed_pixel_timing in include/drm/drm_edid.h):
    pclk[2], hact/blank[3], vact/blank[3], sync lo/lo/vnibbles/hi[4],
    image size mm[3], borders[2], misc[1].
    flags 0x1E = digital separate sync, positive H and V polarity."""
    hb = hact + hfp + hs + hbp - hact
    vb = vact + vfp + vs + vbp - vact
    pc = pclk_khz // 10  # units of 10 kHz
    return [
        pc & 0xFF, (pc >> 8) & 0xFF,
        hact & 0xFF, hb & 0xFF,
        ((hact >> 8) & 0xF) << 4 | ((hb >> 8) & 0xF),
        vact & 0xFF, vb & 0xFF,
        ((vact >> 8) & 0xF) << 4 | ((vb >> 8) & 0xF),
        hfp & 0xFF, hs & 0xFF,
        ((vfp & 0xF) << 4) | (vs & 0xF),
        ((hfp >> 8) & 0x3) << 6 | ((hs >> 8) & 0x3) << 4 | ((vfp >> 8) & 0x3) << 2 | ((vs >> 8) & 0x3),
        hmm & 0xFF, vmm & 0xFF,
        ((hmm >> 8) & 0xF) << 4 | ((vmm >> 8) & 0xF),
        0, 0,  # borders
        flags,
    ]


def text_descriptor(tag, text):
    """18-byte text descriptor: 5-byte header, then data padded to 13 with
    spaces and terminated by 0x0a per EDID convention."""
    data = text.encode("ascii") + b"\x0a"
    assert len(data) <= 13
    data += b" " * (13 - len(data))
    return [0, 0, 0, tag, 0] + list(data)


def std_timing(xres, ratio, refresh):
    """Standard timing slot. bits 7:6 aspect — the kernel's drm_mode_std()
    (drm_edid.c) has no EDID 1.4 aspect reinterpretation: 00 = 16:10,
    11 = 16:9 for any revision >= 3, so 16:9 must be encoded as 0b11."""
    return [(xres // 8) - 31, (ratio << 6) | (refresh - 60)]


def main():
    # -- Base block --------------------------------------------------------
    emit(0x00, "header", 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00)
    # Manufacturer "NXC", 5-bit letters relative to '@', big-endian.
    mfg = ((ord("N") - ord("@")) & 0x1F) << 10 | ((ord("X") - ord("@")) & 0x1F) << 5 | (ord("C") - ord("@")) & 0x1F
    emit(0x08, "mfg 'NXC'", (mfg >> 8) & 0xFF, mfg & 0xFF)
    emit(0x0A, "product code", 0x01, 0x00)
    emit(0x0C, "serial", 0x00, 0x00, 0x00, 0x00)
    emit(0x10, "week/year 2026", 0x00, 2026 - 1990)
    emit(0x12, "EDID 1.4", 0x01, 0x04)
    emit(0x14, "digital input", 0x80)
    emit(0x15, "screen 70x40 cm", 70, 40)
    emit(0x17, "gamma 2.2", 120)
    emit(0x18, "DPMS/sRGB/preferred", 0xEA)
    # sRGB chromaticity, 10-bit values (MSB byte + 2-bit LSBs shared).
    emit(0x19, "R/G LSBs", 0xEE)
    emit(0x1A, "B/W LSBs", 0x91)
    emit(0x1B, "Rx/Ry/Gx/Gy/Bx/By/Wx/Wy MSBs",
         0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54)
    emit(0x23, "established timings", 0x00, 0x00, 0x00)
    # Slot 1: 1920x1080@60; remaining slots unused (0x0101).
    emit(0x26, "std 1920x1080@60", *std_timing(1920, 0b11, 60))
    BYTEMAP.extend([0x01, 0x01] * 7)
    print("  0x28..0x35: 7 unused std timing slots (0x0101)", file=sys.stderr)

    # -- DTD1: preferred 3840x2160@60 (VIC 97) ----------------------------
    BYTEMAP.extend(dtd(594_000, 3840, 176, 88, 296, 2160, 8, 10, 72, 1210, 680))

    # -- DTD2: monitor name ------------------------------------------------
    BYTEMAP.extend(text_descriptor(0xFC, "DP3-Fake-4K"))

    # -- DTD3: range limits covering both modes ----------------------------
    # 13-byte data area: 6 limits, extended-timing flags 0x00, 0x0a end
    # marker, spaces to 13 (matches the kernel template's descriptor3).
    BYTEMAP.extend(text_descriptor(0xFD, "")[:5] + [58, 62, 66, 137, 60, 0x00, 0x0A] + [0x20] * 6)

    # -- DTD4: dummy --------------------------------------------------------
    BYTEMAP.append(0x10)
    BYTEMAP.extend([0x00] * 17)

    # -- Checksum -----------------------------------------------------------
    # 0x7E bytes so far: everything except the extensions flag and the
    # checksum itself, which are emitted together below.
    assert len(BYTEMAP) == 0x7E, f"expected 126 bytes before checksum, got {len(BYTEMAP)}"
    checksum = (-sum(BYTEMAP)) & 0xFF
    emit(0x7E, "extensions/checksum", 0x00, checksum)

    sys.stdout.buffer.write(bytes(BYTEMAP))


if __name__ == "__main__":
    main()
