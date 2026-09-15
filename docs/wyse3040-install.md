# Wyse 3040 installation and maintenance

The Wyse is an Ethernet-connected server with an ephemeral root filesystem
and a remote Nix builder. Its host entry is in
[outputs/default.nix](../outputs/default.nix).

## 1. Hardware

The Atom x5-Z8350 system has about 1.8 GB usable RAM, an 8 GB soldered eMMC,
and a replaceable SD card. Limited RAM makes local builds impractical.

[hardware.nix](../hosts/wyse3040/hardware.nix) carries the machine-specific
boot and service workarounds; keep them out of the generated
[hardware-configuration.nix](../hosts/wyse3040/hardware-configuration.nix),
which the installation recipe regenerates.

## 2. Storage and boot

### 2.1 Disk layout

[disk-config.nix](../hosts/wyse3040/disk-config.nix) uses physical disk IDs,
because `/dev/mmcblkN` enumeration has changed between kernels.

| Device | Recorded ID | Use |
|---|---|---|
| eMMC | `mmc-H8G4a__0x4fa1ec64` | 512 MB EFI partition; remainder unallocated |
| SD | `mmc-SDABC_0xaa000150` | Btrfs root, store, persistent state, and swap |

Verify IDs on the actual target before installation or after replacing media.
Both disks are partitioned by the install recipe.

The firmware uses the removable-media EFI fallback path. GRUB is configured
with `efiInstallAsRemovable = true` and without NVRAM writes. The host also
blacklists `dw_dmac_core` and uses `reboot=efi` for shutdown/reboot problems.
MMC/SDHCI drivers are included in the initrd.

### 2.2 Persistence and wear

The [impermanence capability](../modules/nixos/capabilities/impermanence.nix)
restores `@root` from `@root-blank` before mounting root. Its systemd-initrd
service waits for the Btrfs device and initializes the blank snapshot on first
boot. `/nix` and `/persist` are separate subvolumes; `/persist` is mounted early.

Only the declared persistence list survives root rollback. It includes host
SSH keys, machine identity, NetworkManager state, service data, and selected
user directories. Add required application state to the appropriate persistence
module before relying on it. Docker adds its own persistent state.

The [SD-card capability](../modules/nixos/capabilities/sdcard.nix) uses tmpfs
for `/tmp`, zram before disk swap, bounded journals, GC, optimisation, and TRIM.
These reduce writes and store pressure; they do not replace a data backup.

## 3. Secrets and remote builds

The [host module](../hosts/wyse3040/default.nix) decrypts the builder SSH key to
`/persist/root/.ssh/builder_ed25519`. Its public half must be listed in
`vars.builderClientKeys` on the builder. The
[client capability](../modules/nixos/capabilities/remote-build-client.nix)
uses `vars.builders` and sets local `max-jobs = 0`.

Before a reinstall, preserve the registered host Ed25519 key privately so the
new system can decrypt `secrets/builder.yaml`. For replacement hardware, either
provision that identity deliberately or register a new host key with SOPS and
rewrap the required file. See [secrets](secrets.md).

The current host does not enable the WiFi profiles capability. If WiFi is
needed, configure it explicitly and verify connectivity before removing Ethernet.

## 4. Pre-install checks

1. Back up `/persist`, required user/service data, and host keys off the target.
2. Boot a NixOS live USB using F12. Establish root SSH access over Ethernet.
3. Run `ls -l /dev/disk/by-id/mmc-*` on the target and compare both IDs with
   `disk-config.nix`.
4. Prepare a private `--extra-files` directory containing the registered host
   key at `etc/ssh/ssh_host_ed25519_key` and its public half beside it, with
   ownership and permissions suitable for root SSH keys. Keep it outside Git.
5. Evaluate the configuration on the deployer:

   ```sh
   just check wyse3040
   ```

New `.nix` files must be tracked before flake evaluation. Resolve evaluation
errors and warnings before installation.

## 5. Initial installation or deliberate reinstall

This operation repartitions the configured disks and destroys their existing
data. It is not a routine deployment or an emergency rebuild command.

From the Linux deployer, with `HOST_IP` and `PRIVATE_EXTRA_FILES` set to the
verified target and prepared directory:

```sh
just install-remote wyse3040 "$HOST_IP" --extra-files "$PRIVATE_EXTRA_FILES"
```

The [recipe](../justfile) invokes nixos-anywhere, regenerates hardware
configuration, runs Disko, and installs the system. Inspect the generated file
changes afterward. On the installed system, verify SOPS decryption and builder
access before relying on remote builds. Restore persistent application data
from backup as needed.

For an SD replacement, power down, replace the card, boot the live USB, and
update the disk ID before following this procedure. The original card developed
SDHCI errors and a read-only Btrfs remount; copying its old device ID is not a
substitute for identifying the replacement.

## 6. Routine deployment and recovery

```sh
just check wyse3040
just apply wyse3040
```

`just apply wyse3040` runs Colmena, then attempts an Avahi health check over
`wyse3040.local`, even if deployment fails. It preserves Colmena's exit status.
The current recipe has no IP fallback, and `just apply` without a target does
not run per-host Avahi recovery.

If `.local` resolution fails, use a known IP to inspect the host and, if needed,
restart Avahi:

```sh
ssh "root@$HOST_IP" 'systemctl restart avahi-daemon.socket avahi-daemon.service'
```

For an activation failure, inspect the system journal and use a retained boot
generation when available. For a boot failure, use the console or a live USB
to inspect and recover existing filesystems. Do not run the install recipe
unless you intend to erase and recreate the configured disks.

## 7. Service workarounds

The host's recorded service-start failures included `Operation not permitted`
with `PrivateTmp` enabled. Its workaround replaces `PrivateTmp` with
`TemporaryFileSystem=/tmp /var/tmp`, retaining other hardening. This is a
host-specific observation, not a general incompatibility between tmpfs and
systemd namespaces.

The override covers logind, nscd, hostnamed, and enabled Avahi services. The
wpa_supplicant variant is conditional on `networking.wireless.enable` and
includes `AF_PACKET`; do not assume it applies to every NetworkManager setup.

A failed logind coincided with roughly 25-second SSH login delays and activation
failures. Check its journal before attributing a slow SSH connection to key
exchange. The host also restricts KEX algorithms to classical algorithms;
reassess that restriction using `ssh -vv` timing when updating OpenSSH.

Avahi sometimes failed to reactivate after deployment; the recipe's health
check handles that recorded case. A successful Colmena exit does not establish
that mDNS is working.

## 8. Verification

After deployment, check from the deployer:

```sh
time ssh root@wyse3040.local true
ssh root@wyse3040.local 'systemctl is-active systemd-logind avahi-daemon nscd'
ssh root@wyse3040.local 'systemctl --failed'
ssh root@wyse3040.local 'findmnt /persist; cat /proc/swaps'
```

On the Wyse, inspect `nix show-config` for the configured `builders`, confirm
the root-owned builder key exists with restricted permissions, and test a build
that is not already cached. A substituted `hello` package does not prove remote
execution. Distinguish SSH authentication failures from Nix trusted-user errors;
[remote-builder.nix](../modules/nixos/capabilities/remote-builder.nix) configures
both authorization and the `nix-builder` trust setting.
