# NVIDIA on `briefcase`

A bug log for the NVIDIA cards that have lived in this machine. The
**configuration** is in `hardware/briefcase/gpu/<profile>.nix`; this
file explains **why** each knob is set the way it is, so a future
"clean up" doesn't quietly re-introduce a known failure mode.

The current profile is `hardware/briefcase/gpu/nvidia-turing.nix`.

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

## 3. Why `KWIN_DRM_DISABLE_EXPLICIT_SYNC=1`

### Symptoms it solves

A cluster of three superficially-different failures that all share the
same root cause. Observed in June 2026 on this box (KWin 6.5.4, NVIDIA
580.119.02, kernel 6.12.x):

1. **Login screen freezes after entering the password.** SDDM greeter
   disappears, KSplash never finishes, screen stays on the last greeter
   frame. Switching to a TTY (Ctrl+Alt+F3) and back unfreezes it
   immediately and the session is otherwise fine.
2. **Session "logs out" mid-startup.** You enter the password, KWin and
   KSplash start, then ~10 s later you're back at SDDM. The journal
   shows a clean PAM `Closing session` — no KWin crash, no coredump.
3. **Hard freeze on the second login attempt** after force-rebooting
   from case (1) or (2). Looks identical to a hung kernel: caps-lock
   LED unresponsive, only fix is the power button.

### Root cause

KWin 6.5 enables the Wayland **explicit synchronization** protocol
(`linux-drm-syncobj-v1`) by default. The flow is:

1. KWin submits an atomic DRM commit with an `OUT_FENCE_FD`.
2. NVIDIA's DRM driver is supposed to signal that fence (or fire a
   page-flip event) once the buffer is on screen.
3. KWin's render loop waits for that fence/event before submitting the
   next frame.

On NVIDIA 580.x the very first atomic commit after a DRM master change
(SDDM greeter → user-session KWin, or cold init, or resume) **sometimes
never signals**. KWin's render loop blocks forever on the fence:

- If KWin blocks before plasmashell maps its first surface → symptom (1).
- If KWin times out and `qFatal`s → KWin exits 15 (SIGTERM via the
  watchdog) → `startplasma-wayland` tears the session down cleanly →
  symptom (2). This is exactly what the journal showed for boot −3:
  ```
  sddm-helper-start-wayland: wayland compositor finished 15 QProcess::NormalExit
  sddm-helper: [PAM] Closing session
  ```
  i.e. a *clean* exit, which is why there's no coredump to find.
- Symptom (3) is a consequence of force-rebooting in state (1)/(2):
  ATX standby keeps PCIe at 3.3 V, the GPU never fully power-cycles,
  the next boot's `nvidia.ko` init hits `i2c timeout error e0000000`
  in dmesg, and the wedged state propagates into the new KWin instance.

A TTY switch rescues case (1) because logind drops and re-grants DRM
master, which forces KWin to redo modeset and resets the broken
page-flip state machine.

### The workaround

Setting `KWIN_DRM_DISABLE_EXPLICIT_SYNC=1` makes KWin fall back to the
classic implicit-sync path (kernel-managed dma-buf reservation
objects). NVIDIA 580 implements the implicit path correctly; only the
new explicit syncobj path is racy.

In NixOS:

```nix
environment.sessionVariables.KWIN_DRM_DISABLE_EXPLICIT_SYNC = "1";
```

`environment.sessionVariables` (not `environment.variables`) is the
correct knob — KWin is started by the per-user systemd manager via
`startplasma-wayland`, and `sessionVariables` is what lands in
`/etc/profile` + the systemd user environment.

### Cost

- A small (usually unmeasurable on a single 1080p screen) latency
  increase: implicit sync forces a CPU-side wait point where explicit
  sync could let the GPU pipeline overlap.
- No correctness or stability downside on this driver.

### When to remove it

This whole class of bugs is tracked upstream as
"KWin 6 + NVIDIA explicit sync first-frame hang". To safely drop the
env var you want **all** of:

1. NVIDIA driver ≥ a release whose changelog mentions a fix for
   `linux-drm-syncobj-v1` / first-frame page-flip. As of 580.119.02
   this is not yet the case; watch for it in the 590/600 series.
2. KWin ≥ a release that bumps its required NVIDIA version or that
   includes a "explicit sync resilience" / "first-frame timeout
   recovery" commit.
3. After removing the var, force the failure scenario on purpose
   (SDDM → login → KSplash) **five times in a row** without freeze
   before declaring it fixed. The bug is racy, not deterministic.

If any of those is not true, leave the workaround on. It is cheap.

### If the var doesn't help

Then the real cause is probably **not** explicit sync. Next things to
try, in order:

1. Check if `WAYLAND_DISPLAY` is hardcoded in
   `systemd.user.sessionVariables` — this breaks SDDM regardless of
   GPU driver. See `docs/sddm-wayland-display.md`.
2. Disable the SDDM Wayland greeter (`services.displayManager.sddm.wayland.enable = false;`)
   to avoid the greeter-→-session DRM master handoff entirely. Session
   stays Plasma Wayland.
3. Cold-start the machine (pull the PSU plug for 30 s) to clear any
   wedged GPU state — `reboot` alone doesn't power-cycle the PCIe slot.
4. Collect `journalctl --user -b -1 | grep -iE 'kwin|qFatal|signal'`
   and `coredumpctl list` to confirm whether KWin exited cleanly
   (workaround territory) or actually crashed (driver bug territory).
