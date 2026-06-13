# NVIDIA on `briefcase`

Notes for the RTX 2060 SUPER setup on this machine. These explain **why**
the config in `hardware/briefcase/default.nix` looks the way it does, so
the choices don't get "optimised" back into trouble later.

Card: **NVIDIA GeForce RTX 2060 SUPER** (Turing, TU106, 8 GB VRAM)
Driver: **proprietary `nvidia` 580.x**, `modesetting=1`, `powerManagement=1`

---

## 1. Why proprietary, not the open kernel module

### What "open" actually means

NVIDIA ships two kernel module flavours:

| Flavour | What it is |
|---|---|
| **proprietary** (`nvidia.ko`) | The classic closed-source blob. Mature, supports every consumer card NVIDIA has ever shipped. |
| **open** (`nvidia-open`) | Open-source kernel-side glue (still talks to a closed userspace blob). Officially supported only on **Turing data-center cards, GTX 16xx, and everything Ampere or newer**. Consumer Turing cards (RTX 20 / RTX 20 SUPER) are **not** in the supported list. |

### What goes wrong with open on this card

Setting `hardware.nvidia.open = true` on a TU106 makes the NixOS module
auto-append this to the kernel command line:

```
nvidia.NVreg_OpenRmEnableUnsupportedGpus=1
```

This is a "you asked for it" override that lets the open module bind to a
card NVIDIA itself does not support. It loads, but:

- `dmesg` shows `nvidia-gpu 0000:01:00.3: i2c timeout error` — GPU control
  bus glitches.
- KWin Wayland regularly spams `Key repeat discarded ... compositor doesn't
  seem to be processing events fast enough!` and `GL_INVALID_VALUE`.
- Plasma crashes after some minutes-to-hours, dumping you back to SDDM
  ("auto logout").
- The second login attempt sometimes hard-freezes the entire box, because
  the GPU is left in a wedged state and the new session's modeset hangs.

### Decision

Use the proprietary module on this card:

```nix
hardware.nvidia.open = false;
hardware.nvidia.modesetting.enable = true;   # required for Wayland
```

`modesetting.enable = true` is what gives KWin a usable Wayland DRM
backend — without it KWin falls back to software rendering or refuses to
start.

### When to revisit

Only if either:

- This machine gets a new GPU **Ampere or newer** (RTX 30/40/50 …), where
  open is officially supported and proven stable, **or**
- NVIDIA officially adds Turing consumer cards to the open support list
  (check the release notes for the driver version in use).

Until then, leave `open = false`.

---

## 2. Why `hardware.nvidia.powerManagement.enable = true`

### Symptom it solves

After suspend / resume on Wayland:

- The first frame after wake is corrupt — flicker, black tiles, or a stale
  frame from before suspend.
- Some GL/Vulkan apps (Firefox, Chrome, GTK4 apps with GPU canvases) report
  *GL context lost* and either go black or crash.
- Cursor occasionally disappears until you move it.

### Why it happens (three layers)

1. **Hardware**: VRAM is DRAM. During a standard suspend-to-RAM (ACPI S3),
   the PCIe device drops to D3cold and the GPU **loses power completely**.
   Everything in VRAM is gone.
2. **Driver**: Intel/AMD's open-source drivers participate in the kernel's
   standard DRM memory manager, which automatically evicts every GPU
   buffer to system RAM before suspend and restores it on resume. The
   NVIDIA proprietary driver does **not** plug into this framework — by
   default it just marks every buffer's contents as *undefined* after
   resume.
3. **Compositor**: KWin wakes up, finds all its textures, framebuffers,
   and shader buffers full of undefined data, and renders one frame from
   them before anything else can re-upload. That single frame is what you
   see as "flicker".

### What the option actually enables

`hardware.nvidia.powerManagement.enable = true` in NixOS does three things:

1. Adds module parameters:
   ```
   options nvidia NVreg_PreserveVideoMemoryAllocations=1
   options nvidia NVreg_TemporaryFilePath=/var/tmp
   ```
2. Enables `nvidia-suspend.service`, `nvidia-resume.service`,
   `nvidia-hibernate.service`, hooked into `systemd-suspend.service`
   ordering via `Before=` / `After=`.
3. Those services write `suspend` / `resume` to
   `/proc/driver/nvidia/suspend`. The driver responds by DMA-copying the
   entire VRAM contents to files in `/var/tmp/` before power-down, and
   DMA-copying them back on wake.

### Cost

- Suspend takes **+1 to +3 seconds** (DMA write).
- Wake takes **+1 to +3 seconds** (DMA read).
- `/var/tmp` needs free space roughly equal to the VRAM in use (worst
  case 8 GB on this card; typically 1–2 GB).

Worth it.

### Why this isn't the default in NixOS

- Pre-Maxwell cards (very old) sometimes hang on the
  `/proc/driver/nvidia/suspend` interface.
- The feature stabilised in driver 470 and NixOS module 25.05.
- Enabling it on hardware you don't actually use to suspend is wasted
  disk I/O, so NixOS leaves it opt-in.

---

## 3. Quick reference

Current state in `hardware/briefcase/default.nix`:

```nix
hardware.graphics.enable = true;
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia.open = false;
hardware.nvidia.modesetting.enable = true;
hardware.nvidia.powerManagement.enable = true;
```

Things to check if symptoms come back:

| Symptom | First place to look |
|---|---|
| Auto-logout / KWin freezes | `journalctl --user -b -1 | grep -iE 'kwin|plasmashell'` and `dmesg | grep -i nvidia` |
| Wake-up flicker | confirm `cat /proc/cmdline | grep PreserveVideoMemory` shows `=1`, and `systemctl status nvidia-resume.service` is active |
| Cannot start Wayland session | check `modesetting.enable = true` is still in the config |
| Driver version | `cat /proc/driver/nvidia/version` |
