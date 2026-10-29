#!/usr/bin/env python3
"""Generate the fake-monitor EDID binary used by the briefcase Sunshine
capability (modules/nixos/capabilities/sunshine.nix).

The binary is committed; regenerate and revalidate with:

    python3 sunshine-fake-edid.py > sunshine-fake-edid.bin
    edid-decode sunshine-fake-edid.bin

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
    # Max 12 chars: 13-byte descriptor data area, 0x0a-terminated, space
    # padded. The name is host-agnostic — do not bake a resolution or a
    # connector name into the label.
    BYTEMAP.extend(text_descriptor(0xFC, "Sunshine"))

    # -- DTD3: range limits covering both modes ----------------------------
    # 13-byte data area: 6 limits, extended-timing flags 0x00, 0x0a end
    # marker, spaces to 13 (matches the kernel template's descriptor3).
    BYTEMAP.extend(text_descriptor(0xFD, "")[:5] + [58, 62, 66, 137, 60, 0x00, 0x0A] + [0x20] * 6)

    # -- DTD4: dummy --------------------------------------------------------
    BYTEMAP.append(0x10)
    BYTEMAP.extend([0x00] * 17)

    # -- Checksum -----------------------------------------------------------
    # 0x7E bytes so far. The extensions-count byte participates in the
    # checksum, so append it first and sum over bytes 0..126.
    assert len(BYTEMAP) == 0x7E, f"expected 126 bytes before checksum, got {len(BYTEMAP)}"
    # One CEA-861 extension follows (see the CEA extension below).
    BYTEMAP.append(0x01)
    checksum = (-sum(BYTEMAP)) & 0xFF
    emit(0x7F, "checksum", checksum)

    # -- CEA-861 extension: declare HDMI 2.0 sink capabilities --------------
    #
    # Without this block the connector has no HF-VSDB, so the kernel
    # leaves display_info.max_tmds_clock at 0 and i915 caps the sink at
    # the 165 MHz DVI baseline (intel_hdmi.c hdmi_port_clock_limit):
    # 1080p60 (148.5 MHz) survives but 4K60 (594 MHz) is rejected. The
    # HF-VSDB's Max_TMDS_Character_Rate (600 MHz, > 340 MHz so the
    # kernel honors it) lifts the cap to the source's own DG2 limit.
    # SCDC support is deliberately NOT declared — there is no sink to
    # answer SCDC reads over I2C, and the TMDS cap does not require it.
    ext = []

    def emit_ext(offset, comment, *values):
        ext.extend(values)
        print(f"  ext {offset:#06x}: {' '.join(f'{v:02X}' for v in values)}  ; {comment}", file=sys.stderr)

    # byte 2 = byte offset where DTDs would start: 4-byte header + 6-byte
    # HDMI VSDB (1 header + 5 payload) + 8-byte HF-VSDB (1 header + 7
    # payload) = 18. Parsers read data blocks from byte 4 up to this
    # offset; a zero here hides the VSDBs from some parsers.
    emit_ext(0x00, "CEA-861 tag/rev, DTD offset", 0x02, 0x03, 0x12, 0x00)
    # HDMI 1.4 VSDB: data-block header byte = (tag<<5)|len; tag 3 len 5
    # = 0x65; OUI 00-0C-03 (LSb first); physical address 1.0.0.0. Marks
    # the sink as HDMI (kernel cea_db_is_hdmi_vsdb: tag 3 + this OUI +
    # payload >= 5). Layout copied from the real KTC monitor's EDID.
    emit_ext(0x04, "HDMI VSDB", 0x65, 0x03, 0x0C, 0x00, 0x10, 0x00)
    # HDMI Forum VSDB: ALSO a plain tag-3 vendor block (NOT an extended
    # tag-7 block), OUI C4-5D-D8 (LSb first); version 1;
    # Max_TMDS_Character_Rate 0x78 = 600 MHz (kernel reads hf_scds[5]);
    # SCDC flags 0x00 — no sink exists to answer SCDC reads over I2C,
    # and the TMDS cap does not require SCDC. Kernel
    # cea_db_is_hdmi_forum_vsdb: tag 3 + this OUI + payload >= 7.
    emit_ext(0x0A, "HF-VSDB", 0x67, 0xD8, 0x5D, 0xC4, 0x01, 0x78, 0x00, 0x00)
    ext.extend([0x00] * (127 - len(ext)))  # indices 0..126; checksum is 127
    print(f"  ext 0x40..0x7d: zero padding", file=sys.stderr)
    ext_checksum = (-sum(ext)) & 0xFF
    emit_ext(0x7E, "checksum", ext_checksum)
    assert len(ext) == 128, f"extension must be 128 bytes, got {len(ext)}"
    BYTEMAP.extend(ext)

    sys.stdout.buffer.write(bytes(BYTEMAP))


if __name__ == "__main__":
    main()
