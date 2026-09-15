# H410 idle hard hangs

`briefcase` (MAXSUN MS-TZZ H410M, i3-10105F) had idle/locked-screen freezes
with both the Quadro P620 and Intel Arc A380. Recorded incidents left no
useful kernel panic, pstore entry, or coredump.

The working hypothesis is a platform power-management problem involving CPU
idle states or the PCIe path. The absence of logs and occurrence across GPUs
support investigating the platform; they do not prove an exact electrical
failure or rule out RAM, firmware, and other hardware faults.

## Current mitigations

| Location | Setting | Reason |
|---|---|---|
| [Host module](../hosts/briefcase/default.nix) | `intel_idle.max_cstate=1` | Restrict deep CPU idle states |
| [Arc profile](../hosts/briefcase/gpu/intel-arc-a380.nix) | `pcie_port_pm=off` | Disable PCIe port runtime power management |
| Arc profile | Forced ASPM parameters removed | Avoid the aggressive policy used during power tuning |

The CPU restriction was added on 2026-07-15. A freeze recurred on 2026-08-03
after about seven hours of idle despite the restriction being active. PCIe
port runtime PM was then disabled and forced ASPM removed. See the
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
