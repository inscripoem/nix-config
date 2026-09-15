# NVIDIA profiles on briefcase

The active GPU is [Intel Arc A380](intel-arc-a380.md). The retained
[Turing](../hosts/briefcase/gpu/nvidia-turing.nix) and
[Pascal](../hosts/briefcase/gpu/nvidia-pascal.nix) profiles support switching
back to the RTX 2060 SUPER or Quadro P620 by changing the host's GPU import.
These notes describe the historical NVIDIA setup, not current Arc behavior.

## 1. Driver selection

Both profiles select the proprietary module and enable modesetting. The
Turing choice preserves the locally tested setup after instability with the
open module; it is not a claim that all Turing consumer cards are unsupported
by NVIDIA's open modules. Check the exact driver release and device support
when revisiting the choice. Pascal requires the proprietary module.

The Pascal profile additionally selects `nvidiaPackages.production` and
asserts the version starts with `580.`. If an update trips that assertion,
select a Pascal-supporting package actually present in the pinned nixpkgs.
Do not remove the assertion merely to make evaluation pass or assume a future
legacy attribute already exists.

## 2. Suspend and resume

`hardware.nvidia.powerManagement.enable = true` enables the NVIDIA
suspend/resume integration and video-memory preservation. It was retained
because resume previously produced corrupt frames or lost GL/Vulkan contexts.

The driver needs temporary storage for preserved allocations, configured
through `NVreg_TemporaryFilePath`. Check the generated setting and available
space when changing the driver or GPU. Test suspend/resume with graphical
applications open; successful login alone does not exercise this path.

## 3. KWin explicit-sync workaround

Both profiles export `KWIN_DRM_DISABLE_EXPLICIT_SYNC=1`. The historical
KWin 6.5.4 / NVIDIA 580.119.02 setup showed login frames frozen until a VT
switch, or a session returning to SDDM during startup. Disabling explicit sync
was the adopted workaround for that combination.

Keep it scoped to NVIDIA profiles. Reassess after driver/KWin upgrades using
repeated cold logins, logout/login cycles, and suspend/resume. A short successful
session is weak evidence for an intermittent failure. Check release notes and
logs rather than treating an assumed future version number as the fix.

If the failure persists, inspect KWin logs and coredumps, and check for leaked
[display variables](sddm-wayland-display.md). A login failure, driver crash,
and full-machine idle freeze need separate diagnosis.

## 4. Diagnostic checks

```sh
journalctl --user -b | rg -i 'kwin|qFatal|signal'
journalctl -b -k | rg -i 'nvidia|Xid|drm'
coredumpctl list
```

The H410 machine also froze while idle with both NVIDIA and Intel GPUs.
See [hard-hang investigation](hard-hang-cstate.md) before attributing those
logless failures solely to the NVIDIA driver. The shared CPU power restriction
remains in the host module when GPU profiles change.
