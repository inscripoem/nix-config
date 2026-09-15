# Lix ownership migration on air

Phase 4 was activated by Captain on 2026-09-15 as generation 6. Automated
post-switch checks and reboot acceptance passed on the same date. Phase 3 commit
`9b9a49e` was pushed, and generation 5 remains the rollback anchor.
Do not use `darwin-rebuild check`:
the pinned revision was observed to activate instead of checking.

Evaluation, dry-run, full build, generated-file review and the clean-baseline
NixOS comparison passed on 2026-09-14–15. The built system is
`/nix/store/3w1v4ajlf0h08jg0k0fw7d28743bqbfl-darwin-system-26.11.4cff07d`.
The HM activation and Brewfile are unchanged. On 2026-09-15, the separate
preparation was completed with Captain's authorization: all four files were
backed up and verified, and the installer hook was disabled and unloaded. Evaluation and
build were rerun successfully with the same output. Captain then ran `nhs`;
the active system now matches that reviewed output.

## Ownership and compatibility

`modules/darwin/base/nix.nix` enables system Nix management and explicitly
selects `pkgs.lix`. The locked nixpkgs provides Lix **2.95.2**, the same version
as the installer profile. It is a different package build/store path, not a
switch to upstream Nix. Home Manager keeps `nix.enable = false`.

nix-darwin takes over the client package, `org.nixos.nix-daemon`, build users,
`/etc/nix/nix.conf`, and `/etc/nix/registry.json`. The registry now pins the
unqualified `nixpkgs` reference to this system's locked source, rather than
the global registry's moving `nixpkgs-unstable`. The `nixpkgs=flake:nixpkgs`
lookup is retained; no nonexistent root channel is added to `NIX_PATH`.
Existing user channel lookup remains available when its directory exists.

The Lix installer remains responsible for the APFS volume and its mount
service, `org.nixos.darwin-store`. Keep `/nix/receipt.json`,
`/nix/nix-installer`, and `/nix/var/nix/profiles/default` intact. Do not
uninstall/repair the installation or upgrade its global profile during
acceptance. The old global profile contains the fallback daemon plist.

The 2026-09-14 read-only audit found:

- Lix installer `3.95.0`; current client/daemon package is Lix `2.95.2`.
- `nixbld` GID 350 and 32 `_nixbld` users with UIDs 351–382 match the pinned
  nix-darwin defaults at `system.stateVersion = 6`; no ID migration is needed.
- `/etc/nix/nix.conf` SHA256 is
  `daa9d824601c088f52de3da176e14328ba41e7be3eb450fdf8b93c86f236f722`.
- The comment-only `/etc/nix/nix.custom.conf` SHA256 is
  `a6dee4985bf207d3bec6a3cee28aefb33e60f5d0a91d8c20bbd71b9dadb2e601`.
- Both hashes are recognized by the pinned nix-darwin. Activation backs up
  the originals as `.before-nix-darwin`; it does not merge arbitrary custom
  configuration. Those backup names and `/etc/nix/registry.json` were absent.
- The original daemon plist uses the global profile and logs to
  `/var/log/nix-daemon.log`. The managed daemon uses the selected Lix store
  path and retains this log location.

The settings retain flakes, nix-command, `always-allow-substitutes`, the Lix
trusted cache/key, automatic job count and the shell prompt prefix. The
normal substituter remains cache.nixos.org; the Lix cache remains trusted
for explicit use, not newly added to default downloads. Only root is trusted.
Build users are explicitly configured by nix-darwin. Automatic GC and
optimisation stay off; no sandbox-policy change is introduced.

## Installer shell hook

Before preparation, `systems.lix.nix-installer.nix-hook` was loaded and waiting in
`wait4path` for `/nix/lix-installer`, which does not exist. The actual installer
is `/nix/nix-installer`. Its `repair --help` says the default repair action
repairs shell hooks; it is not evidence of daemon/config repair.

Do not fix the executable path or invoke repair: that would reintroduce an
installer writer for shell files already owned by nix-darwin/HM. Before the
switch, back up the plist, disable this exact service persistently, and
unload it. Preserve the plist itself. **Do not disable the APFS mount service
or the working Nix daemon.** This preparation was completed on 2026-09-15;
the original hook plist remains in place, but the service is disabled and
no longer loaded.

## Before switching

Keep the current terminal open and pause other Nix builds/switches. Do not
garbage-collect either system generation or the installer profile.

Steps 1–4 below have been completed on air. They document the procedure;
do not repeat backup creation or bootout on the already prepared host.

1. Reconfirm that `/run/current-system` and `system-5-link` point to
   `/nix/store/4mqnh0i16vskjb7pzr4yk6jgy1acrgaf-darwin-system-26.11.4cff07d`.
   Recheck the file hashes, build IDs, original profile's daemon plist,
   backup-name absence (including broken symlinks), and that there is no
   unmanaged `/etc/nix/registry.json`. Stop on drift; never overwrite backups.

2. Make a separate root-only backup in a new directory before changing
   anything. For example, after confirming the directory does not exist:

   ```sh
   sudo mkdir -m 700 /var/root/nix-config-phase4-backup-20260915 &&
     sudo cp -p /etc/nix/nix.conf /etc/nix/nix.custom.conf \
       /Library/LaunchDaemons/org.nixos.nix-daemon.plist \
       /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist \
       /var/root/nix-config-phase4-backup-20260915/
   ```

   Verify all four copies and record the global profile's resolved target.
   The non-overwriting directory creation is intentional; stop if it exists.
   Record the hook's current loaded/enabled state for possible recovery.

3. With approval for the preparation, run:

   ```sh
   sudo launchctl disable system/systems.lix.nix-installer.nix-hook
   sudo launchctl bootout system/systems.lix.nix-installer.nix-hook
   ```

   Confirm the exact service is disabled and no longer loaded, while
   `org.nixos.nix-daemon` and `org.nixos.darwin-store` are unchanged. An error
   is not permission to continue without checking what state was reached.

4. Run the non-activating gates and review the generated files:

   ```sh
   git diff --check
   nix eval --no-warn-dirty .#darwinConfigurations.air.config.system.build.toplevel.drvPath
   nix build --no-warn-dirty --no-link --dry-run .#darwinConfigurations.air.config.system.build.toplevel
   nix build --no-warn-dirty --no-link .#darwinConfigurations.air.config.system.build.toplevel
   ```

   After successful preparation and review, Captain runs `nhs` from the
   repository. No real activation is performed by the preparation checks.
   For syntax checks, use the Bash 5.3 interpreter named in `activate`'s
   shebang, not macOS's older `/bin/bash` (which lacks HM's `[[ -v ... ]]`).

## Preparation record (2026-09-15)

- Backup directory: `/var/root/nix-config-phase4-backup-20260915`, owned by
  root:wheel, mode 0700. Each of the four copies matched its original with
  `cmp`; no previous backup was overwritten. Keep this directory through
  live acceptance and any rollback.
- Prior hook state: loaded, enabled, PID 1133 with a `wait4path` child.
  `launchctl disable` and `bootout` both exited 0. The disabled override is
  now present, service lookup reports not found, and no process referencing
  `/nix/lix-installer` remains. Its plist hash is unchanged.
- The Nix daemon is still running as PID 805, runs=1, never exited; its
  plist is unchanged. A daemon-store hash query succeeded.
- The APFS mount job is still loaded, runs=1, last exit=0. This is a one-shot
  job, so its `not running` state after mounting is normal. `/nix` remains
  mounted and the mount plist is unchanged.
- The original global profile still resolves to
  `/nix/store/ckw9rg3mwhrm7h2n271xx7kwh28qd0ww-user-environment`, with Lix at
  `/nix/store/4dw2mganmnsxy31wyjll1vrn3gp5x345-lix-2.95.2`.
- Both configuration hashes and the 32 build-user IDs/GID remain unchanged.
  The `.before-nix-darwin` backup names and registry target remain absent.
  System profile and current-system remain on Phase 3 generation 5.
- Original daemon plist SHA256:
  `be3b0a84ca2777bcc22d59504f97141b57d1ecbb8905835deebd3d63c1b37d2f`.
  Original hook plist SHA256:
  `edb996ab3e03050d794f3227e1a514a048b2c268f9ba7c8ad070751c15af69ff`.
  Unchanged mount plist SHA256:
  `cff647b9deda72edf203e2864da85293e46d583f7a17286d1c7b5a5acdac3edf`.

No installer repair/uninstall, daemon restart, real switch, commit, or push
was performed during preparation. Successful preparation is not yet Phase 4
live acceptance.

## Acceptance

### Post-switch record (2026-09-15)

- `/nix/var/nix/profiles/system` is `system-6-link`; it and
  `/run/current-system` resolve to the reviewed Phase 4 output above.
- A fresh interactive login Zsh resolves `nix` to
  `/run/current-system/sw/bin/nix` and reports Lix 2.95.2. The loaded daemon
  uses `/nix/store/gz67hm146ll3jbkvri3rf33idvjk8bcl-lix-2.95.2/bin/nix-daemon`;
  the live plist matches the generation's plist exactly. The recorded
  activation-time HUP is expected from the reviewed reload script.
- A new local, non-substituted daemon build passed assertions that the
  builder UID is 351–382 and GID is 350. Its output reports UID 351, GID 350:
  `/nix/store/5chpi56f82gh64f6md79bph4d3sk2qkn-air-lix-acceptance-1789475395`.
- `nix.conf` and `registry.json` link through `/etc/static`. Both original
  `.before-nix-darwin` configuration files have their recorded hashes.
  The registry pins the locked nixpkgs source; only root is trusted, and
  cache settings and disabled auto-optimise behavior match the reviewed config.
- All 24 HM file links resolve to the unchanged HM generation's targets.
  Git/Neovim still come from HM; Node from NVM, Bun from its existing install,
  and Go from Homebrew. Fresh shell initialization and the Nix certificate
  path check pass. Brew Bundle `check --no-upgrade` succeeds.
- The old repair hook remains disabled. No Nix GC/optimise services were
  introduced. The APFS mount job, mount plist and original global profile
  remain unchanged; `/nix` is mounted. Generation 5 remains available.
- No additional switch, daemon restart, installer repair/uninstall, old
  profile cleanup, commit or push was performed during verification.

### Reboot acceptance record (2026-09-15)

- Boot time is 20:35:34 Asia/Shanghai. Generation 6 and the reviewed system
  output remain active without another switch.
- `/nix` mounted automatically. The original APFS mount job ran once and
  exited 0; its plist hash is unchanged.
- The managed Lix daemon started at boot (PID 502, runs=1, never exited),
  using the reviewed Lix 2.95.2 store path. The live plist still matches the
  generation's plist. The old installer shell hook remains disabled.
- A fresh login Zsh resolves Lix through `/run/current-system/sw/bin/nix`;
  Git, Neovim, Node, Bun and Go retain their expected sources. The Nix
  certificate path is readable. All 24 HM links and Brew Bundle checks pass.
- A new local, non-substituted daemon build passed with UID 351 and GID 350:
  `/nix/store/72azbvjf59nipgcd2zs324j45lq3l5la-air-lix-reboot-acceptance-1789478618`.
  A daemon-store query also succeeded. Cache/trust/build-user settings remain
  as reviewed; root is still the only trusted user.
- The two automatic config backup hashes, original global profile and
  generation 5 rollback target are intact. No cleanup or extra switch was
  performed. Phase 4 implementation and live acceptance are complete.
  Captain subsequently authorized the whole-file Phase 4 commit and push;
  the pre-commit fetch confirmed origin/main still matched `9b9a49e`.
  Removal of old installation artifacts is not part of that authorization.
  Retain recovery material until cleanup is reviewed.

### Acceptance checklist

- System profile and `/run/current-system` match the reviewed Phase 4 output.
- A new login shell resolves `nix` through `/run/current-system/sw/bin/nix`
  and reports Lix 2.95.2. Retained installer binaries may still appear later
  in PATH; they are rollback copies, not the active owner.
- `launchctl print system/org.nixos.nix-daemon` shows the reviewed Lix store
  path and a running daemon. A daemon-store query and a small uncached build
  succeed; evaluation alone does not verify daemon-side build-user behavior.
- Both original configuration backups have the recorded hashes; the live
  `nix.conf` links through `/etc/static`, and the registry pins nixpkgs.
- Root remains the only trusted user. Build-user IDs are unchanged. No
  scheduled GC/optimise jobs or installer shell repair hook are running.
- All HM links, fresh shell initialization, certificate paths, Brew Bundle
  `check --no-upgrade`, and the existing language-tool command sources pass.
- The APFS mount service and installer profile remain unchanged. Confirm a
  later reboot mounts `/nix` and starts the managed daemon before closeout.

## Rollback

Generation rollback is **not** sufficient to restore the installer config.
The pinned nix-darwin removes stale `/etc/static` links but does not put back
their `.before-nix-darwin` files. Its unmanaged-daemon recovery uses the old
global profile, which must remain installed.

1. Verify generation 5 still identifies the recorded Phase 3 system. Use
   its already-built rebuild command, without evaluating the Phase 4 tree:

   ```sh
   sudo -H /nix/var/nix/profiles/system-5-link/sw/bin/darwin-rebuild --switch-generation 5
   ```

2. Confirm the generation rollback removed only the Phase 4 managed links
   at `/etc/nix/nix.conf` and `/etc/nix/registry.json`. Inspect any remaining
   files/symlinks before proceeding. Restore `nix.conf.before-nix-darwin`
   and `nix.custom.conf.before-nix-darwin` to their original names only when
   those destination names are absent. Preserve the separate root backup;
   if a backup/hash is missing or differs, stop and recover from that copy
   after inspection. Do not blindly overwrite a live managed link.

3. Verify the daemon plist has reverted to the original global-profile
   command. After restoring both config files, restart it with
   `sudo launchctl kickstart -k system/org.nixos.nix-daemon`. Verify a daemon
   query, build, fresh shell and all Phase 3 checks. Build users and the
   APFS mount service should still exist unchanged.

4. The installer shell hook should remain disabled under Phase 3 too, since
   shell ownership remains with nix-darwin/HM. Re-enabling it is a separate
   decision. If deliberately restoring its exact prior state, inspect the
   preserved plist, then `launchctl enable` and `launchctl bootstrap system`
   that plist as root; the observed prior state was a wait on a missing file,
   not a functioning repair service.

If activation fails part-way before updating `/run/current-system`, the
automatic unmanaged-daemon recovery condition may not be met. Inspect the
live plist and config before retrying: restore the original plist from the
root backup, restore the config files without overwriting unrelated files,
and reload that exact service as needed. Do not uninstall Lix, recreate its
build users, or run installer repair as a recovery shortcut.
