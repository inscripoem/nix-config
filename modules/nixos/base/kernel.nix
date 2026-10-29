{ lib, pkgs, ... }:

{
  # Track mainline instead of LTS. Initially motivated by the July 2026
  # briefcase hard-hangs (later diagnosed as a C-state PCIe link-drop on
  # the H410 board — see docs/hard-hang-cstate.md), but still worthwhile
  # for newer nvme / iommu code paths with the KIOXIA EXCERIA.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # Crash forensics: when the kernel notices something is broken, escalate
  # it to a full panic so the last dmesg ring buffer is flushed to pstore
  # (EFI backend, mounted at /sys/fs/pstore) and the box auto-reboots.
  #
  # Motivated by the July 2026 silent hard-hang series on briefcase, which
  # turned out to be a hardware-level PCIe link drop triggered by deep CPU
  # C-states (C2/C3) on the H410 budget board — so far below kernel visibility
  # that even these panic hooks never fired and pstore stayed empty.
  #
  # Root cause & fix: docs/hard-hang-cstate.md (platform replaced 2026-10-26;
  # the host-level intel_idle.max_cstate=1 param was removed with the board)
  # Base sets these at default priority: the server class overrides them
  # with plain assignment, and a host can still use mkForce if needed.
  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkDefault 10;              # auto-reboot 10s after panic
    "kernel.panic_on_oops" = lib.mkDefault 1;       # oops -> panic (so it lands in pstore)
    "kernel.hung_task_panic" = lib.mkDefault 1;     # hung_task_timeout_secs elapsed -> panic
    "kernel.hung_task_timeout_secs" = lib.mkDefault 30;  # trip hung_task after 30s (default 120s) so silent NVMe I/O stalls escalate before the box goes fully dark
    "kernel.softlockup_panic" = lib.mkDefault 1;    # >20s stuck in kernel on one CPU -> panic
    "kernel.hardlockup_panic" = lib.mkDefault 1;    # NMI watchdog trip -> panic
  };
}
