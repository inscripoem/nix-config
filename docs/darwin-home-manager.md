# Home Manager on air

Home Manager owns the shell, Git, SSH configuration, editors, shared CLI tools,
and language toolchain on `air`. The shell uses the same configuration as the
Linux hosts, with explicit Darwin adaptations. The
[migration record](../nix-darwin.plan) contains the original rollout and recovery
generations; it does not record later user-level software removals.

## Configuration ownership

| Source | Responsibility |
|---|---|
| [home/core](../home/core/default.nix) | Shared behavior and CLI tools |
| [shell.nix](../home/core/shell.nix) | Shell integrations, Darwin rebuild aliases, Zsh dot directory, Homebrew environment, OrbStack command/completion paths |
| [home/darwin](../home/darwin/default.nix) | Native 1Password paths, Git file target, Darwin adaptations |
| [toolchain.nix](../home/packs/toolchain.nix) | Node, Bun, pnpm, Yarn, uv, rustup, Go, just, devenv |
| [air.nix](../home/hosts/air.nix) | Toolchain selection, local utility paths, Git identity, LFS/Xet, SSH Includes, activation guards, background-service choices |

There is no host-specific shell initialization module. Host entries may declare
paths for local utilities, but shell startup and aliases belong in the shared
shell module. `air` adds `~/.claude/bin` and `~/.tools` for existing utilities.

Oh My Zsh and its Git/Heroku/pip plugins are not enabled. Atuin, Starship, zoxide,
highlighting, and native completion use the shared integrations; nix-index
supplies command-not-found. On Darwin, Zsh, Nix Bash, and Fish share the Brew
aliases `bs` (`brew search`), `bic` (`brew install --cask`), `bif`
(`brew install --formula`), and `bu`
(`brew update && brew upgrade && brew cleanup`). These are explicit user commands;
Homebrew activation still disables automatic updates, upgrades, and cleanup.
See [Atuin](atuin-zsh.md) for widget ordering.

Darwin shell startup initializes Homebrew, then places the HM profile ahead of
user tool directories and Homebrew. It retains `~/.local/bin`, `~/go/bin`, and
`~/.cargo/bin`, so uv tools, `go install`, and `cargo install` remain usable.
These user-installed tools are not themselves managed by Nix. Initialization
runs once per inherited session so a nested shell can retain a project's
activated environment. Zsh also includes OrbStack's installed completions.

PDM, Poetry, pipx, and Python remain Homebrew software. The toolchain pack's
Python component supplies uv, not a global `python` interpreter. Use `python3`
for the retained Homebrew interpreter or `uv run` for project environments.
Rustup comes from Nix and uses the existing user toolchains in `~/.rustup`.

NVM, Rye, MoonBit, Proto, and Bun's global packages were removed before this
migration. Their initialization is no longer sourced. After verifying the Nix
commands, the standalone Bun, uv, and rustup binaries and their command links
were removed. Their temporary recovery backup was subsequently deleted at the
user's request. The existing Rust toolchains, uv environments, and Go/Cargo
user-installed tools remain, except for Cargo's old `exa`, which was uninstalled.
The Nix `exa` command is a compatibility link to `eza`.

The duplicate Homebrew formulae `go`, `fastfetch`, `fd`, `git`, `neovim`,
`starship`, `unzip`, and `zoxide` were explicitly uninstalled with automatic
dependency removal disabled. Keep Homebrew's `git-lfs` for `git-xet`, `ripgrep`
for `opencode`, and `xz` for Python and other formulae. Nix copies on PATH do not
satisfy Homebrew's dependency tracking. Activation still uses `cleanup = "none"`.

Zerobrew's `~/.local/bin/zb` and the entire `/opt/zerobrew` tree were removed,
including the old packages under `prefix/Cellar`, the store, and caches.
The active shell configuration did not reference it, and no backup was retained.

After generation 8 activated the Bash compatibility guard, the unused
`~/.antigen` bundles and caches were removed. The four plugin checkouts had no
local commits or tracked edits; the only untracked theme files were generated
copies with an Antigen header. Active shell files did not reference this tree.

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
4. Verify native 1Password, OrbStack, Git Xet, and the declared toolchain are
   available. Evaluate and build the Darwin target using the
   [deployment guide](nix-config-orchestration.md#validation-and-deployment).
5. After the user runs `nhs`, test a fresh shell, Atuin keys, editor aliases,
   toolchain command paths, HTTPS, Git signing, and GitHub/private/OrbStack SSH
   connections. Check Bash and Fish as well as the default Zsh. Commands from
   an old terminal may retain the old PATH and cached command locations.

## Shell and toolchain migration checks

Before switching, record the current system generation and command paths.
Evaluate all hosts after changing the shared shell; build the complete `air`
system without activation and inspect its generated shell files.

After switching, `node`, `npm`, `bun`, `pnpm`, `yarn`, `uv`, `rustup`, `cargo`,
`rustc`, `go`, `just`, and `devenv` should resolve through the HM profile.
Verify that `pdm`, `poetry`, and `pipx` still resolve through Homebrew, and that
user tools such as `speedtest-cli` remain available. Test a clean login shell,
an interactive non-login shell, and a nested shell with an active project
environment. Removing Oh My Zsh must not break Tab, Up, or Ctrl-R.

The Nix profile supplies the interactive `bash`; macOS retains its own
`/bin/bash` 3.2 for scripts that explicitly select it. On Darwin, `.bashrc`
initializes the environment and returns early for Bash versions older than 4,
before Home Manager's modern shell options, completions, and prompt hooks.
The system Bash therefore gets the declared PATH without those interactive
enhancements. Verify both `/bin/bash` and the Nix Bash after changing this guard;
do not replace the system binary or automatically re-exec a different shell.

The preparatory cleanup rebuilt `speedtest-cli` 2.1.3 using uv-managed Python
3.13.5 after its old Rye interpreter was removed. Other project environments
that referenced a removed Rye interpreter need to be recreated with uv.

## Recovery

No backup of the removed standalone CLI binaries is retained. Reinstall any
required standalone tools or Homebrew packages separately; a normal reinstall
may select a newer version. The retained `/opt/homebrew/etc/gitconfig` was not
removed by this cleanup.

For this shell/toolchain change, use the system generation recorded immediately
before switching and restore the corresponding repository configuration. The
preparation used generation 6, but verify the live generation rather than
assuming that number is still current. Retain it until the new shell is accepted.
A generation rollback does not reinstall the removed NVM/Rye/MoonBit/Proto
software or their user environments. Reinstall a required runtime separately;
the original migration record is not a complete rollback of those removals.

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
