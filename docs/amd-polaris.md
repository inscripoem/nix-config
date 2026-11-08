# AMD Polaris on briefcase

The active [AMD Polaris profile](../hosts/briefcase/gpu/amd-polaris.nix)
configures the Dell Radeon Pro WX 5100 (`1002:67c7`). The retained
[Intel Arc A380 profile](../hosts/briefcase/gpu/intel-arc-a380.nix) and
NVIDIA profiles remain available for hardware comparison.

## Configuration decisions

| Setting | Purpose |
|---|---|
| `amdgpu` in initrd | Early kernel graphics initialization |
| Xorg `modesetting` | Mesa-based display stack |
| `LIBVA_DRIVER_NAME=radeonsi` | Select the Mesa VA-API backend for both Sunshine services |
| `pcie_aspm=off` | Preserve the existing platform-level ASPM mitigation |
| No connector in the profile | DisplayPort enumeration can change when cables or dummy plugs move |
| User Sunshine `capture=wlr` | Capture through niri's `wlr-screencopy` support without an XDG Portal approval |
| Greeter Sunshine `capture=wlr` | Capture the pre-login greeter through `dms-greeter`'s niri Wayland socket |

The host installs `libva-utils`, `nvtopPackages.amd`, and `radeontop`.
Redistributable firmware is enabled at the host level. Sunshine's KMS capture
on this host failed with `EGL_BAD_MATCH (0x3009)` while importing the scanout
DMA-BUF, so both the user and pre-login greeter services use wlr-screencopy.
This is an observed Sunshine/KMS path failure, not evidence of a Polaris-only
driver defect.

## Display and fake output

The software fake output is disabled for the initial Polaris bring-up.
Sunshine therefore captures the first connected output at its native mode.
The physical monitor's current connector name is intentionally not stored in
configuration.

A headless 4K setup can use a physical DisplayPort dummy plug. It presents a
normal EDID-bearing sink to amdgpu, so when it is the only connected output no
connector name is needed and `fakeOutput.enable` remains false. This is the
preferred setup for routine headless use.

Use a native DisplayPort sink or dummy. A DP-to-DVI adapter reports
`subconnector = DVI-D` and an TMDS encoder; single-link DVI rejects the EDID's
4K30 timing at 266.64 MHz and can retain only the 4K17 timing at 151.10 MHz.
Native DP avoids that physical link limit.

When a real monitor and a dummy plug are connected at the same time, Sunshine
still needs a rule for which output to capture. Disconnecting the unused sink
removes that ambiguity. A future EDID-matching selector could resolve the
connector at runtime; until then, do not pin a `DP-x` name for routine
hotplugging.

Do not force a virtual DisplayPort connector without first validating mode
selection on amdgpu. The retained Arc notes explain why a forced connector
without DPCD is unreliable.

## Verification

```sh
lspci -nnk | rg -A4 'VGA|3D|Display'
niri msg outputs
LIBVA_DRIVER_NAME=radeonsi vainfo
systemctl --user show sunshine -p ExecStart
journalctl --user -b -u sunshine
journalctl -b -u sunshine-greeter
```

The user service should report `Screencasting with Wayland's protocol` and
must not attempt `portalgrab`. The greeter should report KMS capture. Exercise
Moonlight login handoff, logout, and a complete reboot after activation.
