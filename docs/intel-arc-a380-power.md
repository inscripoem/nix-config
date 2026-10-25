# Arc A380 power observations

The platform moved to B760M (i5-13400TEF) on 2026-10-26. `pcie_port_pm=off`
was an H410 hard-hang mitigation and was removed with that board. ASPM is
now enabled through the standard `pcie_aspm.policy=powersave` kernel
parameter in the [current profile](../hosts/briefcase/gpu/intel-arc-a380.nix)
— kernel policy over capability-negotiated links, not the "forced ASPM"
register tuning removed 2026-08-03 during the H410 freeze investigation.
What applied to the H410 lives in [idle hangs](hard-hang-cstate.md).

## Current measurements (B760M, 2026-10-26)

| State | Power |
|---|---|
| Idle, display scanning (DP), ASPM L1 enabled | ~18.4 W — i915 hwmon energy counter, 30 s window, RC6 ~41% |
| Expected ASPM L1 contribution | ~1 W (H410 measurement with the same card; clean-window re-measurement pending) |

For calibration: Windows reviews of this exact card (Sparkle A380 Genie,
TechPowerUp) idle around 10 W or below on a Windows 11 desktop. The gap is
driver policy — the Linux driver keeps GDDR6 in a higher gear while a
display scans out and enters shallower package idle states — not something
host configuration can change. Headless Linux reports reach single digits
with ASPM enabled; that state requires no attached display.

## Historical measurements (H410)

On the Sparkle A380 with i3-10105F / H410:

| Setup | Observed GPU idle power |
|---|---|
| Before forcing ASPM | About 18–19 W |
| Forced ASPM with `powersupersave` | About 17–18 W |

The roughly 1 W reduction did not justify retaining the policy while
investigating full-system freezes. Power after removing it was expected to
return to the earlier range; that expectation is not a new measurement.

The CPU root port did not advertise L1.1/L1.2 support in the recorded setup,
although the card's internal switch did. Changing the Linux ASPM policy cannot
supply a missing link-partner capability.

## Reading diagnostics

The GPU endpoint reported PCIe 1.0 x1, while the upstream switch port reported
PCIe 3.0 x8. Inspect the complete `lspci -t` topology and both link partners
before concluding the motherboard slot is limited to the endpoint's reported
width.

Use the GPU's hwmon energy counter over a measured interval to estimate power;
DRM card and hwmon numbers can change between boots. Compare under the same
display mode and workload. Large `nvtop` memory totals may include allocations
not attributed to visible processes; they are not evidence of an idle power
problem by themselves.
