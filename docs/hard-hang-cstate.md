# Silent hard-hang from deep CPU C-states on H410

`briefcase` (MAXSUN MS-TZZ H410M, i3-10105F) suffered
progressively-frequent hard freezes starting around July 2026. Both the
NVIDIA Quadro P620 and the Intel Arc A380 were affected; the freeze left
zero trace in the kernel ring buffer, pstore, or journalctl.

## Root cause

When the CPU enters deep C-states (C2 MWAIT 0x33 / C3 MWAIT 0x60), the
H410 budget board silently drops the PCIe link between the CPU root port
(00:01.0) and the downstream PCIe switch (01:00.0). The GPU falls off
the bus → the display freezes → the kernel never sees a fault.

Because the link drop happens at the hardware/firmware level, none of
the kernel panic detectors we configured fire:

- `kernel.hardlockup_panic` — NMI watchdog never trips
- `kernel.softlockup_panic` — CPUs are not stuck in-kernel; they simply
  can't reach the GPU
- `kernel.hung_task_panic` — no task is blocked long enough
- pstore always empty on next boot

The freeze only occurs when the machine is **idle** — deep C-states are
only entered when all cores are quiescent. Active use keeps the CPU in
C0/C1 and the PCIe link stays alive. This also explains why the
diagnosis session (with constant interactive load) could run for over
an hour without incident.

## Diagnosis

The key forensic signals:

1. **Kernel command line** showed `max_cstate=9` and no C-state
   restrictions — the CPU was free to enter C2/C3.
2. **PCIe switch power policy** (`/sys/bus/pci/devices/0000:01:00.0/power/control`)
   was `auto`, allowing runtime PM to drop the link.
3. **Pattern**: every crash boot ended silently during idle or shortly
   after screen lock / 1Password auto-lock. Active sessions never
   crashed.
4. **Both GPUs affected**: NVIDIA crashes (boot -9, -8) and Arc
   crashes (boot -4, -3, -1) all shared the same silent-cut-off
   pattern, ruling out a GPU driver bug.

Searching for GPU errors (NVIDIA Xid, i915 GPU HANG/reset), disk I/O
errors, MCE, thermal throttling, and memory corruption turned up
nothing.

## Fix

Limit the CPU to C1 at deepest, preventing the PCIe link from dropping:

```nix
# hosts/briefcase/default.nix
boot.kernelParams = [ "intel_idle.max_cstate=1" ];
```

The kernel panic hooks in `modules/nixos/base/kernel.nix` are retained
as a safety net for future incidents, but they will not catch
C-state-induced PCIe link drops (which happen below kernel visibility).

## Verification

1. Lock the screen and leave the machine idle for ≥ 30 minutes.
2. If the freeze does not recur, the fix is confirmed.

## Alternative root causes considered & ruled out

| Suspect | Evidence against |
|---------|-----------------|
| Disk / NVMe failure | No I/O errors, media errors, or bad blocks in any boot. BTRFS clean. |
| GPU driver bug (i915 or nvidia) | Both GPUs, two different kernel versions (6.18.5, 7.1.3), two different nixpkgs snapshots — all crashed identically. |
| Thermal | CPU 50–52 °C, NVMe 52 °C, GPU 47 °C under normal load. |
| RAM | No MCE or EDAC errors. (memtest86+ not yet run.) |
| Arc A380 BAR2 resize failure | BAR2 warning is cosmetic for desktop use; it limits VRAM performance but does not cause link drops or freezes. |
| nixpkgs update | Crashes span both pre-update (NVIDIA, nixpkgs 26.05) and post-update (Arc, nixpkgs 26.11) generations. |
