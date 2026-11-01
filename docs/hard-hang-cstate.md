# H410 idle hard hangs

Historical record for the retired H410 platform, replaced 2026-10-26 —
see [Resolution](#resolution-2026-10-26) at the end. The section
[Reusing the H410 + i3-10105F hardware](#reusing-the-h410--i3-10105f-hardware)
preserves the configuration that platform requires.

`briefcase` (MAXSUN MS-TZZ H410M, i3-10105F) had idle/locked-screen freezes
with both the Quadro P620 and Intel Arc A380. Recorded incidents left no
useful kernel panic, pstore entry, or coredump.

The working hypothesis is a platform power-management problem involving CPU
idle states or the PCIe path. The absence of logs and occurrence across GPUs
support investigating the platform; they do not prove an exact electrical
failure or rule out RAM, firmware, and other hardware faults.

## Mitigations (removed 2026-10-26, see Resolution)

| Location | Setting | Reason |
|---|---|---|
| [Host module](../hosts/briefcase/default.nix) | `intel_idle.max_cstate=1` | Restrict deep CPU idle states |
| [Arc profile](../hosts/briefcase/gpu/intel-arc-a380.nix) | `pcie_port_pm=off` | Disable PCIe port runtime power management |
| Arc profile | Forced ASPM parameters removed | Avoid the aggressive policy used during power tuning |
| [Host module](../hosts/briefcase/default.nix) | `RuntimeWatchdogSec=30s`, `intel_oc_wdt` blacklisted | Feed the PCH iTCO watchdog so a whole-machine hang auto-resets |

The CPU restriction was added on 2026-07-15. A freeze recurred on 2026-08-03
after about seven hours of idle despite the restriction being active. PCIe
port runtime PM was then disabled and forced ASPM removed. Another freeze
recurred on 2026-09-22 around 12:02 after eight days of uptime, with the same
signature: the journal stops mid-write, no kernel panic, and pstore stays
empty. None of the existing mitigations had blocked it, so the iTCO runtime
watchdog was added afterwards as a recovery-only last line of defense — it
restarts the box but neither observes nor fixes the underlying fault. See the
[power measurements](intel-arc-a380-power.md) for the small saving abandoned
by that change.

Removing forced ASPM is not the same as explicitly disabling all firmware
ASPM behavior. Inspect the running link state when testing this hypothesis.

## Historical observations

These observations come from the July–August 2026 investigation. They are
comparison points for a recurrence, not fresh measurements or proof of a cause.

| Observation | Diagnostic significance |
|---|---|
| On the August 3 recurrence, cpuidle exposed only `POLL` and `C1_ACPI` | The CPU idle restriction was active, but did not prevent every freeze |
| `/sys/bus/pci/devices/0000:01:00.0/power/control` was `auto` on the GPU-path switch | PCIe port runtime PM remained enabled before the second mitigation |
| Forced ASPM with `powersupersave` had enabled link state L1 | CPU idle limits did not also disable PCIe low-power policies |
| Quadro P620 and Arc runs, across kernels 6.18.5 and 7.1.3, ended with similar silent freezes | Investigation extended beyond a single GPU driver or system generation |
| Searches found no NVIDIA Xid, i915 hang/reset, disk I/O, MCE, or EDAC errors | The available logs did not identify a failing component; memory testing was still outstanding |
| Recorded normal-load temperatures were CPU 50–52 °C, NVMe 52 °C, GPU 47 °C | No overheating was observed in those samples; they were not measurements at the instant of failure |

Device addresses can change after hardware changes. Confirm the PCIe topology
before comparing the recorded switch path with a new boot.

## Verification and recurrence

Check `/proc/cmdline`, available cpuidle states, PCIe power state, and the kernel
journal after activating a change. Test normal use and at least an overnight
locked/idle period. Earlier runs survived several days before another freeze,
so a 30-minute pass cannot establish a fix.

If it recurs, preserve the boot journal and record workload, uptime, display
state, and active parameters. Revisit firmware, memory, power delivery, and the
board; the original investigation did not include a completed memory test.

The [kernel module](../modules/nixos/base/kernel.nix) retains panic/watchdog
settings for detectable faults. Empty logs do not establish that the rest of
the hardware is healthy or that these detectors can observe every failure.

## Resolution (2026-10-26)

The platform was replaced: i3-10105F + MAXSUN MS-TZZ H410M → i5-13400TEF +
MAXSUN MS-Terminator B760M D4 (BIOS H7.8G). The board was retired, not
repaired — the 2026-08-03 and 2026-09-22 freezes both happened with every
mitigation active, and no root cause was confirmed.

Consequences in this repo:

- `intel_idle.max_cstate=1` and the `intel_oc_wdt` blacklist were removed
  from `hosts/briefcase/default.nix`.
- `pcie_port_pm=off` was removed from the Arc GPU profile.
- `RuntimeWatchdogSec=30s` is kept as a recovery-only net; iTCO_wdt was
  verified to own `watchdog0` on the new board.
- ASPM is disabled at every layer as a hard-freeze diagnostic (2026-10-31,
  after nine freezes): `pcie_aspm=off` in the Arc profile plus all BIOS ASPM
  options Disabled. This supersedes the 2026-10-26 configuration
  (`pcie_aspm.policy=powersave`) and its "consumer-desktop firmware does not
  program ASPM" rationale — the firmware was later found with every ASPM
  option Enabled, `_OSC` does not grant the OS the PCIe power-management
  control bit, and the r8169 driver manages RTL8125B ASPM outside the kernel
  policy scope.

## Recurrence on B760M (2026-11-01)

One silent freeze occurred with the platform in its current configuration:
the boot started 18:21:15, the journal stopped mid-write at 19:16:23 after
2h55m of uptime, and the machine was power-cycled at 19:18:22. The last entry
was a telemetry POST from a desktop application; no shutdown sequence
followed.

Recorded state:

| Item | Value |
|---|---|
| Kernel parameters | `pcie_aspm=off`, `i915.enable_guc=2` |
| BIOS ASPM | all options Disabled |
| Workload | Sunshine stream connected 18:21:54 and still connected; no local GPU inference (OCR ran on Colab) |
| GPU errors | none — no `GPU HANG`, no reset, no forcewake timeout for the whole boot |
| Fault messages | no panic, soft lockup, RCU stall, OOM, MCE, or EDAC |
| Memory pressure | earlyoom never crossed its threshold (last report at boot: 99.7% available) |

Two i915 engine wedges occurred earlier the same day (`rcs0` at 17:51:57 and
`vcs1` at 18:13:18) during concurrent Sunshine encode and OpenVINO inference.
Those logged `GPU HANG`, a heartbeat reset, and `Failed to reset chip`; they
are a different signature from this freeze.

The historical investigation recorded that every earlier freeze happened
during idle or shortly after screen lock, and that active sessions never
crashed. This freeze happened during an active Sunshine stream with
continuous desktop activity, so it does not match that pattern and may be the
i915 path above escalating into a kernel-level hang before i915 could log a
reset.

This was the first recorded recurrence after the 2026-10-31 `pcie_aspm=off`
change, so disabling ASPM at every layer did not prevent it. B760 provides no
ECC path and the platform exposes no EDAC interface, so DRAM errors would not
appear in the journal.

A second freeze followed 66 minutes later, on the corrected GPU parameters.
The boot started 19:21:08 with `i915.enable_guc=3` and `i915.enable_dc=0`
(log shows `GUC: submission enabled`, `SLPC enabled`, `RC enabled`), the
journal stopped mid-write at 20:27:03, and the machine was power-cycled; the
next boot started 20:35:26. A Sunshine stream had been connected since
19:22:29 and no local inference was running.

Diagnostics were again empty: no i915 error, no hung task (the 120 s detector
never fired), no hard lockup, no panic, and no iTCO watchdog reset despite a
30 s timeout. Enabling GuC submission and disabling display DC states did not
change the outcome, which is expected if these freezes are a separate failure
mode from the i915 engine wedges.

Reachability was tested during the wait before the power cycle and failed:
neither Tailscale nor ICMP got a reply for 120 s. The kernel itself stopped
rather than just the compositor, and the machine could not recover on its own
even though the iTCO watchdog was armed.

An overnight Memtest86+ run passed (owner report, 2026-11-01). Memtest
exercises DRAM in isolation; it does not cover load-dependent timing, power
delivery, or bus/DMA faults, so DRAM is deprioritised rather than eliminated.

Storage is deprioritised as well: the system disk was replaced before this
recurrence. The current root btrfs subvolume `@root` on `nvme1n1p2` (KIOXIA
EXCERIA G2 2 TB, firmware ECFA17.3) was created 2026-10-30 19:10, and the
19:16 freeze happened on that installation, so the old system disk cannot be
the common cause.

smartd still reports `Self-Test Log error count increased from 0 to 1` for
both NVMe drives, including the new one. An aborted self-test caused by an
unclean reboot also produces such an entry, so this needs `smartctl -a` to
separate a real media failure from an artifact of the freezes.

## Mitigation parameters (as of 2026-11-01)

Every kernel parameter currently applied against the hard freeze, and the file
that sets it:

| Parameter | Set in | Purpose |
|---|---|---|
| `pcie_aspm=off` | `hosts/briefcase/gpu/intel-arc-a380.nix` | Kernel ASPM subsystem off; BIOS ASPM is disabled by hand as well and does not appear in `/proc/cmdline` |
| `intel_idle.max_cstate=1` | `hosts/briefcase/default.nix` | Cap CPU idle at C1; `intel_idle` is the active driver, so this is the effective cap |
| `processor.max_cstate=1` | `hosts/briefcase/default.nix` | ACPI `processor` idle cap for the fallback path |
| `idle=nomwait` | `hosts/briefcase/default.nix` | Avoid MONITOR/MWAIT idle, the mechanism blamed in the July 2026 H410 diagnosis |
| `rcu_nocbs=0-15` | `hosts/briefcase/default.nix` | Offload RCU callbacks from all 16 CPUs |
| `iommu=disable` | `hosts/briefcase/default.nix` | Disable DMA remapping |
| `i915.enable_guc=3` | `hosts/briefcase/gpu/intel-arc-a380.nix` | GuC submission + HuC; also enables SLPC and context-level reset |
| `i915.enable_dc=0` | `hosts/briefcase/gpu/intel-arc-a380.nix` | Keep the display out of DC3/5/6 |
| `i915.disable_power_well=0` | `hosts/briefcase/gpu/intel-arc-a380.nix` | Keep display power wells powered |
| `i915.enable_sagv=0` | `hosts/briefcase/gpu/intel-arc-a380.nix` | Disable SAGV |

The `i915.*` entries only exist on Arc hosts. The `intel_idle`, `processor`,
`idle`, `rcu_nocbs` and `iommu` entries live in the host module and survive a
GPU swap.

Why they were stacked: the freeze is intermittent (roughly hourly under load,
one or two per day otherwise), so a stable run has to last several multiples
of that interval before it means anything. The set was applied together to
reach a stable machine quickly. If the freezes stop, remove entries one at a
time to attribute the effect; a reversal test (remove the whole set and watch
for a return within a few hours) is the strongest single check.

## Reusing the H410 + i3-10105F hardware

If the retired board and CPU are pressed into service elsewhere, apply all
of the following — each line was load-bearing on that platform:

```nix
# hosts/<host>/default.nix
boot.kernelParams = [ "intel_idle.max_cstate=1" ];   # C2/C3 drops the PCIe link
boot.blacklistedKernelModules = [ "intel_oc_wdt" ];  # iTCO_wdt must win watchdog0
systemd.settings.Manager.RuntimeWatchdogSec = "30s"; # recovery-only net

# GPU profile (any discrete GPU)
boot.kernelParams = [ "pcie_port_pm=off" ];          # port runtime PM drops the link
```

Do **not** enable `pcie_aspm.policy=powersave` on that board — forced ASPM
was removed 2026-08-03 during the freeze investigation and only ~1 W was at
stake. Caveats: the mitigations reduced but never eliminated the freeze
rate (two incidents happened with all of them active), and a completed
memory test was never run on that platform.
