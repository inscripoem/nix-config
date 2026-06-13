# Agent Guidelines for `nix-config`

Hard rules any AI assistant MUST follow when modifying this repo.

## 1. Verify before "done"

After **any** edit to a `*.nix` file, run at least one of:

- `nix eval --no-warn-dirty .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (default)
- `nix build --no-link --dry-run .#nixosConfigurations.<host>.config.system.build.toplevel` (when touching packages / overlays)
- `sudo nixos-rebuild dry-activate --flake .#<host>` (when touching activation / systemd / PAM)

Hosts: `briefcase` (primary), `vm`.

A change is only "done" when the chosen command exits 0 with no `error:` or
"will become an error" warnings. Don't ignore warnings — fix them in the
same edit pass.

New `.nix` files MUST be `git add`-ed before evaluation; flakes ignore
untracked files.

The user runs `nhs` themselves. Don't trigger a real rebuild unsolicited.

## 2. Layout

- `configuration.nix` — system-level (services, kernel, networking, PAM, firewall)
- `hardware/<host>/` — per-host hardware
- `home/<group>/` — home-manager modules; add a new file and import it in
  the group's `default.nix`
- `docs/` — long-form rationale for non-obvious decisions (e.g. `docs/nvidia.md`).
  Consult before touching the related config; update when you change the
  decision it documents.

## 3. Git policy

- Never `git commit` or `git push` without an explicit user request.
- `git add` only files this task actually changed; never `git add -A`.

## 4. Language

Reply in Simplified Chinese. Code, paths, and commands stay English.
