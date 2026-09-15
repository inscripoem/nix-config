# Arc A380 power observations on H410

Forced ASPM was removed on 2026-08-03 after recurring idle freezes. The
[current profile](../hosts/briefcase/gpu/intel-arc-a380.nix) uses
`pcie_port_pm=off`; do not restore the old tuning merely to reproduce the
lower measurement. See [idle hangs](hard-hang-cstate.md).

## Historical measurements

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
