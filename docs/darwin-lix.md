# Lix on air

[nix.nix](../modules/darwin/base/nix.nix) makes nix-darwin the owner of Lix,
its daemon, build users, `nix.conf`, and the flake registry. Home Manager keeps
`nix.enable = false` to avoid a second configuration writer.

The migration used Lix 2.95.2 on both sides, with matching `nixbld` GID 350 and
32 build users at UIDs 351–382. Activation and reboot checks completed on
2026-09-15. Recovery generations and backups are recorded in
[the migration record](../nix-darwin.plan).

## Ownership boundaries

The Lix installer still owns the APFS volume and `org.nixos.darwin-store` mount
service. Preserve `/nix/receipt.json`, `/nix/nix-installer`, and
`/nix/var/nix/profiles/default`. The global profile supplies the fallback daemon
when reverting to installer ownership.

The managed registry pins `nixpkgs` to the system's locked source.
`NIX_PATH` retains `nixpkgs=flake:nixpkgs`. Cache settings retain the Lix cache
as trusted for explicit use; the normal substituter remains cache.nixos.org.
Only root is trusted. Automatic GC and optimisation are disabled.

## Installer shell hook

`systems.lix.nix-installer.nix-hook` is disabled and unloaded; its plist is
preserved. It previously waited for the missing `/nix/lix-installer`, while the
actual executable was `/nix/nix-installer`.

Do not repair that path or run installer shell repair while nix-darwin/HM owns
shell initialization. Keep `org.nixos.darwin-store` and the working Nix daemon
enabled. The obsolete hook and the APFS mount service have separate roles.

## Before transferring ownership on another installation

These steps are already complete on `air`.

Keep the current terminal open and pause other Nix builds and switches during
the transfer. Preserve the rollback generations and installer profile; do not
garbage-collect them while they are needed for recovery.

1. Inspect the installed Lix version, build-user IDs, daemon command, global
   profile target, and existing configuration. Check the pinned nix-darwin
   activation logic accepts those files; it does not merge arbitrary custom
   `nix.conf` contents.
2. Back up `nix.conf`, `nix.custom.conf`, the daemon plist, and the installer
   hook plist in a new root-only directory. Verify the copies and record the
   original profile target and service state. Existing `.before-nix-darwin`
   files must not be overwritten.
3. Disable and unload the installer shell hook, preserving its plist. Verify
   the mount service and daemon remain intact.

   For an installation with this exact hook loaded, run:

   ```sh
   sudo launchctl disable system/systems.lix.nix-installer.nix-hook
   sudo launchctl bootout system/systems.lix.nix-installer.nix-hook
   ```

   Check `sudo launchctl print-disabled system` for the disabled override.
   `sudo launchctl print system/systems.lix.nix-installer.nix-hook` should then
   report that the service cannot be found. If either change fails, inspect
   the reached state before continuing. Do not repeat `bootout` on the already
   prepared `air`.
4. Evaluate, preview, and build the Darwin output. Review generated configuration
   and activation scripts before the user switches. For shell syntax checks,
   use the interpreter in the generated script's shebang, not macOS's older
   `/bin/bash`.

See [validation commands](nix-config-orchestration.md#validation-and-deployment).
At the migration's pinned revision, `darwin-rebuild check` performs activation
and must not be used as a dry run.

## Verification

After changing Lix ownership, check:

- A fresh login shell resolves `nix` through `/run/current-system/sw/bin/nix`.
- `launchctl print system/org.nixos.nix-daemon` identifies the intended Lix
  executable; `/var/log/nix-daemon.log` has no startup failure.
- A daemon query and a new, non-substituted build succeed. Evaluation alone
  does not exercise daemon build-user permissions.
- `nix.conf` and `registry.json` link through `/etc/static`; the registry,
  cache settings, and trusted users match the declared configuration.
- HM links, shell initialization, certificates, and Homebrew remain functional.
- After reboot, `/nix` mounts and the daemon starts. The APFS mount job is a
  one-shot job, so `not running` after a successful mount is normal.

## Rollback

Generation rollback does not restore the installer's configuration files.
The pinned nix-darwin removes stale managed links but does not restore their
`.before-nix-darwin` backups. Keep the original global profile installed.

1. Verify generation 5 matches the pre-Lix system in the migration record.
   Use its built rebuild command:

   ```sh
   sudo -H /nix/var/nix/profiles/system-5-link/sw/bin/darwin-rebuild --switch-generation 5
   ```

2. Inspect `/etc/nix/nix.conf` and `/etc/nix/registry.json` after rollback.
   Restore `nix.conf.before-nix-darwin` and `nix.custom.conf.before-nix-darwin`
   to their original names only when the destinations are absent. Compare
   backups against the recorded hashes; use the separate root backup if
   necessary. Do not overwrite a live managed link or unrelated file.
3. Confirm the daemon plist uses the original global-profile command. After
   restoring configuration, restart the daemon:

   ```sh
   sudo launchctl kickstart -k system/org.nixos.nix-daemon
   ```

4. Check a daemon query, build, fresh shell, and store mount. Leave the installer
   shell hook disabled: HM still owns the shell in generation 5.

If activation failed before updating `/run/current-system`, automatic fallback
to the unmanaged daemon may not run. Inspect the live plist and configuration;
restore the original daemon plist from the root backup and reload that service
as needed. Installer repair/uninstall or recreating build users is not part of
this recovery procedure.
