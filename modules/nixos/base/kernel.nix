{ config, pkgs, ... }:

{
  # Track the mainline kernel instead of the LTS default. Motivated by the
  # July 2026 briefcase hard-hangs whose only kernel breadcrumb was a
  # 6.12.65 `alloc_tagging_slab_alloc_hook` warning in the shmem fallocate
  # path — that mm-tagging regression is fixed in the 6.13+ series. Also
  # gives newer nvme / iommu code paths that keep the KIOXIA EXCERIA in
  # better shape between resets.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Crash forensics: when the kernel notices something is broken, escalate
  # it to a full panic so the last dmesg ring buffer is flushed to pstore
  # (EFI backend, already mounted at /sys/fs/pstore) and the box reboots
  # on its own instead of sitting frozen until we hit the power button.
  # Motivated by the July 2026 silent hard-hang series on briefcase where
  # journalctl just cut off mid-log with no panic trace and pstore was
  # empty on the next boot.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;              # auto-reboot 10s after panic
    "kernel.panic_on_oops" = 1;       # oops -> panic (so it lands in pstore)
    "kernel.hung_task_panic" = 1;     # hung_task_timeout_secs elapsed -> panic
    "kernel.hung_task_timeout_secs" = 30;  # trip hung_task after 30s (default 120s) so silent NVMe I/O stalls escalate before the box goes fully dark
    "kernel.softlockup_panic" = 1;    # >20s stuck in kernel on one CPU -> panic
    "kernel.hardlockup_panic" = 1;    # NMI watchdog trip -> panic
  };
}
