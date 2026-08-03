# Intel Arc A380 on `briefcase`

GPU profile: `hosts/briefcase/gpu/intel-arc-a380.nix`

Replaced the previous NVIDIA Quadro P620 (Pascal) with an Intel Arc A380
(DG2/Alchemist, PCI ID `0x56a5`). The machine keeps the existing X11 /
SDDM / Sunshine architecture; this page records the profile-specific
knobs and how to verify the stack is healthy.

## Key knobs

- **`services.xserver.videoDrivers = [ "modesetting" ]`**
  Modern Intel (Gen12+/Arc) uses the modesetting DDX; no `intel` or
  `xe` DDX is required.

- **`boot.initrd.kernelModules = [ "i915" ]`**
  Load the i915 kernel module early so the root filesystem (if on ZFS /
  LUKS) never blocks on the GPU.

- **`boot.kernelParams`**:
  - `i915.enable_guc=2` — HuC only; GuC submission is disabled
    because it caused GPU hangs on this host (see git 77ac815).
  - `pcie_port_pm=off` — no PCIe port runtime PM; the H410 firmware
    silently drops the GPU link on idle low-power states, causing a
    hard hang (see `docs/hard-hang-cstate.md`). This replaced the
    earlier `pcie_aspm=force` / `powersupersave` experiment.

- **`hardware.graphics.extraPackages`**:
  - `intel-media-driver` — VA-API `iHD` backend for hardware
    decode/encode (H.264, HEVC, AV1).
  - `vpl-gpu-rt` — oneVPL / QSV runtime for Intel media engines.
  - `intel-compute-runtime` — OpenCL and Level Zero runtime for GPU
    compute.

- **`environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD"`**
  Forces `va-api` consumers (ffmpeg, mpv, browsers) onto the modern
  `iHD` backend instead of the legacy `i965` stub.

- **`hardware.intel-gpu-tools.enable = true`**
  Ships `intel_gpu_top` for live GPU utilization monitoring without
  root.

- **Firmware**
  The Arc A380's GuC/HuC microcode lives in `linux-firmware`, which is
  already pulled in by `hardware.enableRedistributableFirmware = true`
  in `hosts/briefcase/default.nix`.

## Verification

```bash
# VA-API hardware decode working (should list iHD + AV1/H265/H264)
vainfo

# Kernel/i915/GuC/DRM messages — look for i915 loaded, GuC firmware
# loaded, no i915 probe errors for 56a5
dmesg | grep -E 'i915|xe|GuC|drm'

# Live GPU engine utilization (no sudo required)
intel_gpu_top
```

## Roadmap: switch to Wayland

The current X11 setup is stable and meets the pre-login Sunshine
requirement, but Wayland on Intel Arc has matured. Switching requires
co-ordinated changes across a few modules:

1. **Display manager**
   Change `modules/nixos/desktop/display-managers.nix`:
   - Set `services.displayManager.defaultSession = "plasmawayland"`.
   - Enable `services.displayManager.sddm.wayland.enable = true`.

2. **Sunshine / pre-login capture**
   On Wayland, screen capture without a logged-in session requires DRM
   / KMS access:
   - Set `services.sunshine.capSysAdmin = true` so Sunshine can open
     `/dev/dri/card0` directly.
   - Redesign the `sunshine-sddm` root systemd service (in
     `modules/nixos/capabilities/sunshine.nix`) to capture the SDDM
     Wayland greeter. This may require `pipewire` + `xdg-desktop-portal`
     screencast, or a dedicated KMS capture path. Investigate whether
     SDDM's Wayland compositor exposes a DRM master that Sunshine can
     share.

3. **KRDP**
   Plasma's built-in RDP server (`kcm_krdpserver`) becomes a viable
   non-streaming alternative for guests that cannot run Moonlight.

4. **Validation gate**
   Before treating Wayland as stable on this box, re-test the
   remote-desktop pre-login flow end-to-end:
   - Boot → SDDM Wayland greeter visible via Moonlight.
   - Password entry → KDE session handoff.
   - Logout → SDDM greeter returns without Sunshine restart loops.
