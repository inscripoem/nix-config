# Intel Arc A380 on briefcase

[The Arc profile](../hosts/briefcase/gpu/intel-arc-a380.nix) configures the
DG2/Alchemist A380 (`0x56a5`). It is selected by the
[host module](../hosts/briefcase/default.nix); retained NVIDIA profiles are
available for hardware changes.

## Configuration decisions

| Setting | Purpose |
|---|---|
| Xorg `modesetting` driver | Mesa-based X11 display stack |
| `i915` in initrd | Early kernel graphics initialization |
| `i915.enable_guc=3` | GuC submission + HuC (DG2 default); keeps SLPC and context-level reset available |
| `i915.enable_dc=0` | Disable display DC states; avoids DMC power-well handshakes interfering with GT forcewake |
| `pcie_aspm=off` | Kernel ASPM disabled on every link (RTL8125B workaround, ~2-4 W idle) |
| `intel-media-driver`, `LIBVA_DRIVER_NAME=iHD` | VA-API decode/encode |
| `vpl-gpu-rt` | oneVPL media runtime |
| `intel-compute-runtime` | OpenCL and Level Zero |
| `hardware.intel-gpu-tools.enable` | GPU monitoring integration |

The host enables redistributable firmware. The profile installs
`nvtopPackages.intel`. Recheck kernel support and actual initialization
logs before changing GuC/HuC settings.

See [idle hangs](hard-hang-cstate.md) and [power observations](intel-arc-a380-power.md)
for platform limitations.

## Verification

```sh
vainfo
journalctl -b -k | rg -i 'i915|xe|GuC|HuC|drm'
intel_gpu_top
```

Inspect reported VA-API profiles and initialization errors. Exercise actual
video playback or Sunshine encoding while monitoring the GPU; library presence
alone does not prove hardware acceleration is in use.

## Display backend changes

The default SDDM/Plasma session remains X11 for
[pre-login Sunshine capture](remote-desktop.md). niri is also
installed. Moving the default session to Wayland requires testing capture,
input, audio, login handoff, logout, and reboot. A Wayland greeter needs its
own capture design; do not assume enabling `capSysAdmin` alone supplies one.
