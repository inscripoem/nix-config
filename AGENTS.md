# Agent Guidelines for `nix-config`

Hard rules any AI assistant MUST follow when modifying this repo.

## 1. Verify before "done"

After **any** edit to a `*.nix` file, run at least one of:

- `nix eval --no-warn-dirty .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (default)
- `nix eval --no-warn-dirty .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath` (Darwin or shared Home Manager changes)
- `nix build --no-link --dry-run .#nixosConfigurations.<host>.config.system.build.toplevel` (when touching packages / overlays)
- `sudo nixos-rebuild dry-activate --flake .#<host>` (when touching activation / systemd / PAM)

After **any** edit to QML under `modules/nixos/desktop/dms-plugins/`, run
`just lint-qml`. The gate type-checks against the locked dux-shell source:
syntax errors, duplicate ids, member-level mismatches qmllint can prove,
and qs.* resolution breakage all fail the run. Cross-scope id references
inside Component/delegate bodies are exempt by style. Member checking is
partial by qmllint's limits (reliable mainly on parent-chain receivers);
typos via ids or `Theme.*` singletons are a known gap. Runtime behavior
still needs a DMS plugin reload to confirm.

NixOS hosts: `briefcase` (primary), `vm`, `nutshell` (WSL).
Darwin host: `air`.

A change is only "done" when the chosen command exits 0 with no `error:` or
"will become an error" warnings. Don't ignore warnings — fix them in the
same edit pass.

New `.nix` files MUST be `git add`-ed before evaluation; flakes ignore
untracked files.

The user runs `nhs` themselves. Don't trigger a real rebuild unsolicited.

## 2. Layout

- `outputs/default.nix` — host declarations and configuration outputs
- `modules/nixos/` — system defaults, classes, and optional capabilities
- `modules/darwin/` — shared nix-darwin configuration
- `hosts/<host>/` — per-host hardware
- `home/<group>/` — home-manager modules; add a new file and import it in
  the group's `default.nix`
- `docs/` — long-form rationale for non-obvious decisions (e.g. `docs/nvidia.md`).
  Consult before touching the related config; update when you change the
  decision it documents.
- Every package added to `pkgs/` MUST ship with an update mechanism in
  `scripts/update-versions.sh` (auto-bump section; for commit-pinned
  sources with local patches, a section that tracks upstream HEAD and
  re-fetches the hash — patches are validated at build time). Follows are
  the only exception: nixpkgs overrides that ride the flake's nixpkgs
  input need no section. State the mechanism in the package's `.nix`
  header comment.

## 3. Git policy

- Never `git commit` or `git push` without an explicit user request.
- `git add` only files this task actually changed; never `git add -A`.

## 4. Language

Reply in Simplified Chinese. Write documentation in English; preserve literal
UI messages and user-defined names in their original language. Code, paths,
and commands stay English.

## 5. Commit hygiene

- A single file's changes must land in one commit. Never split them
  across commits — partial rollback would otherwise break evaluation.
- Commit messages follow `scope: description` format. Scope is the
  affected area (e.g. `installer`, `home/creative`, `toolchain/node`,
  `wezterm`). Description is lowercase, no period at the end.
  Examples:
  - `installer: add headless ISO builder and centralize SSH public key`
  - `home/creative: add zrythm`
  - `toolchain/node: add node, pnpm and yarn`
