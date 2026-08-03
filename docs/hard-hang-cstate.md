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

### Round 1: cap CPU C-states (2026-07-15)

Limit the CPU to C1 at deepest, preventing the PCIe link from dropping:

```nix
# hosts/briefcase/default.nix
boot.kernelParams = [ "intel_idle.max_cstate=1" ];
```

### Round 2: close the PCIe-side low-power channels (2026-08-03)

`max_cstate=1` held for ~5 days (boot -4, -3 ran 3.5d + 2.2d without
incident) but a freeze **recurred** on 2026-08-03 (boot -1, after ~7 h of
idle, log cut at 09:37:04). The CPU-side cap was confirmed active
(cpuidle only exposes POLL + C1_ACPI), so the drop must come from the
**PCIe-side** low-power channels the diagnosis noted but the first fix
did not close:

- The GPU-path PCIe switch `0000:01:00.0` had `power/control=auto`
  (portdrv runtime PM allowed to suspend the link).
- `pcie_aspm=force` + `pcie_aspm.policy=powersupersave`
  (added 2026-07-16, see `docs/intel-arc-a380-power.md`) put the link
  into ASPM L1 when idle.

Both are removed/disabled now:

```nix
# hosts/briefcase/gpu/intel-arc-a380.nix
boot.kernelParams = [
  "i915.enable_guc=2"      # HuC only
  "pcie_port_pm=off"       # no PCIe port runtime PM
  # pcie_aspm=force and pcie_aspm.policy=powersupersave removed
];
```

Cost: roughly 1 W of GPU idle power (the L1 substates that would make
ASPM worthwhile are unavailable on this H410 platform anyway).

The kernel panic hooks in `modules/nixos/base/kernel.nix` are retained
as a safety net for future incidents, but they will not catch
C-state/ASPM-induced PCIe link drops (which happen below kernel
visibility).

## Verification

1. Lock the screen and leave the machine idle for ≥ 30 minutes.
2. If the freeze does not recur, the fix is confirmed.

Note: the 2026-08-03 recurrence happened after ~7 h of idle, so a
short idle test passing is necessary but not conclusive — treat one
full overnight idle cycle without a freeze as the real gate. If it
recurrs again with `pcie_port_pm=off`, the remaining suspect is the
H410 board itself and a motherboard swap is the next step (swapping
only the CPU will not help — the defect is in the board firmware).

## Alternative root causes considered & ruled out

| Suspect | Evidence against |
|---------|-----------------|
| Disk / NVMe failure | No I/O errors, media errors, or bad blocks in any boot. BTRFS clean. |
| GPU driver bug (i915 or nvidia) | Both GPUs, two different kernel versions (6.18.5, 7.1.3), two different nixpkgs snapshots — all crashed identically. |
| Thermal | CPU 50–52 °C, NVMe 52 °C, GPU 47 °C under normal load. |
| RAM | No MCE or EDAC errors. (memtest86+ not yet run.) |
| Arc A380 BAR2 resize failure | BAR2 warning is cosmetic for desktop use; it limits VRAM performance but does not cause link drops or freezes. |
| nixpkgs update | Crashes span both pre-update (NVIDIA, nixpkgs 26.05) and post-update (Arc, nixpkgs 26.11) generations. |
