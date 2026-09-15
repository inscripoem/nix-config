# Home Manager on air

Home Manager owns the shell, Git, SSH configuration, editors, and shared CLI
tools on `air`. Existing language runtimes remain configured in the host's
legacy shell module. The [migration record](../nix-darwin.plan) contains the
completed rollout and recovery generations.

## Configuration ownership

| Source | Responsibility |
|---|---|
| [home/core](../home/core/default.nix) | Shared behavior and CLI tools |
| [home/darwin](../home/darwin/default.nix) | Native 1Password paths, Git file target, Zsh dot directory, Darwin adaptations |
| [air.nix](../home/hosts/air.nix) | Git identity, LFS/Xet, SSH Includes, activation guards, background-service choices |
| [legacy-shell.nix](../home/hosts/air/legacy-shell.nix) | Host-specific PATH, existing runtimes, certificates, OrbStack, plugins, and aliases |

When migrating a tool to Nix, remove its manual initialization from the legacy
module in the same change. Keep this machine's local paths out of the shared
Darwin layer.

HM supplies Oh My Zsh and highlighting. Atuin, Starship, and zoxide initialize
through their shared integrations; nix-index supplies command-not-found.
The HM user bin directory takes precedence over retained installations, and
Zsh deduplicates PATH. See [Atuin](atuin-zsh.md) for widget ordering.

Darwin disables HM's `mandb` cache because the pinned Fish manuals fail its
whatis parser. Manual pages remain available; the generated `apropos` index
and index-based Fish completion for `man` are omitted. Pueue is not imported,
and `air` disables tealdeer's scheduled updater.

## Git and SSH

Git uses HM's `~/.gitconfig`; the XDG Git target is disabled to avoid competing
global files. Git signing uses the native 1Password app. Git Xet remains an
external command, while HM enables Git LFS.

SSH uses the native 1Password socket and shared GitHub-over-port-443 policy.
The generated configuration includes OrbStack's `~/.orbstack/ssh/config` and
`~/.ssh/config.local`. The latter is a private, user-owned regular file:
Nix never reads its contents or copies it to the store. Keep it in a private
backup; a public checkout cannot reconstruct it. See [SSH](ssh-agent.md).

## Restoring or onboarding the user environment

Keep a working terminal open until a new login shell has been tested.

1. Restore `~/.ssh/config.local` as a readable, user-owned regular file.
   The activation guard rejects a missing file or symlink.
2. Inspect enabled HM targets, existing files, their parent directories, and
   `.backup` names. Resolve collisions without overwriting earlier backups:

   ```sh
   nix eval --no-warn-dirty --json \
     .#darwinConfigurations.air.config.home-manager.users.inscripoem.home.file \
     --apply 'files: map (f: f.target) (builtins.filter (f: f.enable) (builtins.attrValues files))'
   ```

   Save a private inventory before changing files. For each target, record
   whether it is absent, a regular file, or a symlink; record symlink targets
   without following them, the intended backup name, and whether that backup
   already exists. Include parent symlinks and dangling links. This distinguishes
   files to restore from links that should simply be moved away during recovery.
   A list of HM targets alone does not capture their original state.

3. Preserve any `~/.config/nvim` symlink itself before linking HM files.
   Do not modify its SpaceVim target. HM rejects that parent symlink or an
   existing `init.vim`, which conflicts with the managed `init.lua`.
   The original air migration saved the link as `~/.config/nvim.backup`.
   On a machine with the same SpaceVim layout, the guarded move is:

   ```sh
   test -L "$HOME/.config/nvim" &&
     test "$(readlink "$HOME/.config/nvim")" = "$HOME/.SpaceVim" &&
     test ! -e "$HOME/.config/nvim.backup" &&
     test ! -L "$HOME/.config/nvim.backup" &&
     mv -n "$HOME/.config/nvim" "$HOME/.config/nvim.backup"
   ```

   If a check fails, inspect the actual layout before choosing a backup path.
   Record this parent-link backup separately. Do not repeat the move on the
   already migrated `air`, or use `force = true` to bypass HM file conflicts.
4. Verify native 1Password, OrbStack, Git Xet, and retained runtimes are
   available. Evaluate and build the Darwin target using the
   [deployment guide](nix-config-orchestration.md#validation-and-deployment).
5. After the user runs `nhs`, test a fresh shell, Atuin keys, editor aliases,
   HTTPS, Git signing, and GitHub/private/OrbStack SSH connections.

## Recovery

A system generation rollback does not restore pre-HM dotfiles. If undoing HM
adoption, first follow [Lix recovery](darwin-lix.md#rollback) when crossing
back to an installer-managed generation. Then verify the intended generation
against the [migration record](../nix-darwin.plan).

Use the saved inventory to recover each target:

- For a pre-existing file, inspect the current HM link, move it to an unused
  recovery name, and restore its matching backup.
- For a target that was originally absent, move away only the link confirmed
  to belong to this HM installation. Do not remove the containing data directory.
- For the Neovim parent link, preserve the new `.config/nvim` directory under
  an unused name before restoring `nvim.backup` as the parent symlink.

Keep unrelated files, histories, private keys, and `.SpaceVim` intact. If the
inventory is missing, inspect links and backups individually; the current HM
target list cannot reconstruct which files existed before migration.

The old Antigen installation is not a reliable recovery dependency: the
migration record says it was removed. Inspect restored shell files for
`.antigen/bundles` references and restore the required dependency or adapt those
files before using them as a working shell. Do not assume a generation rollback
reinstalls external tools.
