# Intel Arc A380 idle power on H410

> **Status (2026-08-03): ASPM force is REMOVED.** The `pcie_aspm=force`
> + `pcie_aspm.policy=powersupersave` parameters below were reverted in
> `hosts/briefcase/gpu/intel-arc-a380.nix` and replaced with
> `pcie_port_pm=off`, because the H410 firmware silently drops the GPU
> PCIe link when it idles into a low-power state (hard hang, zero logs —
> see `docs/hard-hang-cstate.md`). The ~1 W that ASPM L1 saved here was
> not worth a full-system freeze. The tuning notes below are kept as
> historical record.

`briefcase` (MAXSUN MS-TZZ H410M, i3-10105F) with a Sparkle Intel Arc A380
(DG2, PCI ID `0x56a5`) idles at a higher GPU power draw than the same card
on a newer platform. This page records why, and what was changed.

GPU profile: `hosts/briefcase/gpu/intel-arc-a380.nix`

## Initial state

- GPU idle power: ~18–19 W measured via `/sys/class/drm/card1/device/hwmon/hwmon1/energy1_input`.
- PCIe ASPM: `Disabled` on every link in the GPU path.
- `nvtop` reported ~4 GB of "VRAM used" at idle, but the visible user
  processes only accounted for ~300 MB. The rest is driver/compositor
  buffers and nvtop's i915 reporting granularity.

## PCIe link width is a reporting bug

`lspci -vvv` shows the GPU endpoint (`03:00.0`) as PCIe 1.0 x1. This is a
known Intel Arc firmware bug: the downstream nodes of the card's internal
PCIe switch report incorrect link attributes. The real link is read from
the upstream switch port (`01:00.0`), which negotiates **PCIe 3.0 x8** with
the CPU root port. The motherboard's single x16 slot is working correctly.

## ASPM tuning

The H410 BIOS only exposes `Auto` and `Force L0s` for ASPM. Setting
`pcie_aspm=powersave` alone is not enough because the ACPI FADT declares
"system does not support PCIe ASPM", and the kernel disables ASPM based on
that flag.

The fix is to force ASPM on and select the most aggressive policy:

```nix
# hosts/briefcase/gpu/intel-arc-a380.nix
boot.kernelParams = [
  "i915.enable_guc=3"
  "pcie_aspm=force"
  "pcie_aspm.policy=powersupersave"
];
```

After reboot, every link from the CPU root port to the GPU endpoint shows
`ASPM L1 Enabled`.

## L1 substates are not available

The i3-10105F / H410 Comet Lake CPU root port does not advertise
`L1SubCap`, so **L1.1 / L1.2 substates cannot be enabled**. The Arc A380's
internal switch supports them, but the link partner does not. This is a
platform limitation, not a driver or configuration issue.

`powersupersave` still helps slightly (~1 W) because it enables the deepest
basic L1 behavior that the platform supports.

## Final state (historical, pre-2026-08-03)

- ASPM policy: `powersupersave`
- All GPU links: `ASPM L1 Enabled`
- GPU idle power: **~17–18 W**

On this hardware, 17–18 W is normal and already optimized. Intel's own
guidance says Arc cards can reach <7 W idle only when L1 substates are
enabled, which requires a newer platform.

## Related configuration changes

- `hosts/briefcase/gpu/intel-arc-a380.nix`: added `pcie_aspm=force` and
  `pcie_aspm.policy=powersupersave`.
- **2026-08-03**: both parameters **removed** (ASPM L1 suspected in the
  recurring hard hang; see `docs/hard-hang-cstate.md`), replaced with
  `pcie_port_pm=off`. Expected GPU idle power returns to ~18–19 W.
- `environment.systemPackages` in the same file: added `nvtopPackages.intel`
  and `furmark` for monitoring and stress testing.
