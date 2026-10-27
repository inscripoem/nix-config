# Ad-hoc software tools

How this repo handles software that is not permanently installed: temporary
execution of nixpkgs-packaged commands (`comma`) and unpatched third-party
binaries (`appimage-run`, `steam-run`, `nix-ld`, `nix-alien`). Decisions below
were made after reviewing community usage (NixOS Wiki, Discourse, nixpkgs
issues) in October 2026.

## Inventory

| Tool | Purpose | Status here |
|---|---|---|
| `comma` | Run a nixpkgs command without installing: `, cmd` | Installed on all platforms via [nix-index-database](https://github.com/nix-community/nix-index-database) ([nix-index.nix](../home/core/nix-index.nix)) |
| `appimage-run` | Run a downloaded `.AppImage` in an FHS environment | Installed on Linux hosts only ([home/core/packages.nix](../home/core/packages.nix)) |
| `steam-run` | Run any binary inside the Steam FHS runtime | Installed where gaming is enabled ([gaming.nix](../modules/nixos/capabilities/gaming.nix), briefcase only) |
| `nix-alien` | Auto-detect missing shared libraries via nix-index | Not installed; used ad hoc via `nix run` |
| `nix-ld` | System-level loader shim for unpatched binaries | Enabled on all NixOS hosts ([nix-ld.nix](../modules/nixos/base/nix-ld.nix)) |

## comma

Wraps `nix shell -c` together with the nix-index database: `, <cmd>` looks up
which package provides the command, builds an ephemeral shell, and runs it
without touching the profile. Complements `programs.nix-index` in
[nix-index.nix](../home/core/nix-index.nix), which only *suggests* a package
when a command is not found; comma *executes* it.

Wired through the
[nix-index-database](https://github.com/nix-community/nix-index-database)
flake input, imported in [home/core/default.nix](../home/core/default.nix) so
every host (including air) gets it:

- `programs.nix-index-database.comma.enable` adds `comma-with-db` — a comma
  wrapper pinned to the weekly prebuilt database (the 1 MB "small" variant,
  filenames only; enough for command lookup).
- The same module swaps `programs.nix-index.package` for the full-database
  wrapper (103 MB on x86_64-linux, 64 MB on aarch64-darwin, store cost) and
  symlinks that database to `~/.cache/nix-index/files` by default
  (`programs.nix-index.symlinkToCacheHome`), so the
  `command_not_found_handler` works out of the box and external tools reading
  the default path (e.g. ad-hoc `nix run github:thiagokokada/nix-alien`) see
  it too.
- The database refreshes with `flake update`; there is no local scan or
  manual `nix-index` run.
- `comma` caches the last-used package per command name and may keep running a
  GC'd-generation version; set `COMMA_CACHING=1` to always resolve fresh.
- It does not conflict with the nix-index `command_not_found_handler`
  integration — comma is invoked explicitly with the `,` prefix.

## appimage-run

Runs an AppImage inside a `buildFHSEnv` environment, supplying the standard
paths (`/lib64/ld-linux-x86-64.so.2`, `/usr/lib`) the image expects. Linux
only — guarded by the existing `isLinux` section in packages.nix so air stays
evaluable.

- Intended for quick manual trials of downloaded images: `appimage-run
  ./tool.AppImage`.
- Not a substitute for packaging. Repo policy is to package AppImages properly
  (`appimageTools.extract` + `appimageTools.wrapType2`, see
  [notion-electron.nix](../pkgs/notion-electron.nix) and the WeChat package);
  use that route when an app becomes a daily driver.
- Some AppImages still fail (bundled binaries with unusual needs); those need
  proper packaging with explicit dependencies.
- The `boot.binfmt` integration (`programs.appimage.binfmt`, executes
  `./x.AppImage` directly) is deliberately not enabled.

## steam-run

Exposes the FHS runtime that Steam itself uses: `steam-run ./binary` or
`steam-run bash` for a standard-layout shell. Installed inside the gaming
capability next to `steamcmd`, so it only exists on hosts with
`modules.capabilities.gaming.steam.enable` (currently briefcase).

- Nearly zero closure delta: the Steam FHS environment is already in the
  closure via `programs.steam`; this entry only adds the wrapper.
- `steam-run` depends on the unfree Steam client
  ([nixpkgs #232640](https://github.com/NixOS/nixpkgs/issues/232640)). On hosts
  without Steam, `steam-run-free` is the standalone variant.
- Useful beyond games: testing installers, debugging binaries that fight with
  nix-ld, or poking around in a "normal" Linux filesystem layout.

## nix-alien (not installed)

Enumerates a binary's shared-library dependencies with `ldd`, resolves them
against the nix-index database, and builds an environment on the fly.
Deliberately not installed:

- [nix-ld](https://wiki.nixos.org/wiki/Nix-ld) is already enabled everywhere
  and is the community-standard first line; its library list in
  [nix-ld.nix](../modules/nixos/base/nix-ld.nix) is hand-maintained and the
  established workflow is "run it, read the `error while loading shared
  libraries` line, add the library".
- When automatic dependency discovery is genuinely needed, run it without
  installing:
  `nix run github:thiagokokada/nix-alien -- ./binary`
  (it also requires the nix-index database, which comma already needs).
- Installing it permanently would add a flake input plus a Python toolchain
  for a rare operation.

## Rollback

Each tool is an independent package entry; removing it takes effect on the
next switch with no other cleanup:

- `comma` — remove the module import from
  [home/core/default.nix](../home/core/default.nix), the
  `programs.nix-index-database.comma.enable` line from
  [nix-index.nix](../home/core/nix-index.nix), and the
  `nix-index-database` input from [flake.nix](../flake.nix)
- `appimage-run` — remove from the `isLinux` section of the same file
- `steam-run` — remove `pkgs.steam.run` from
  [gaming.nix](../modules/nixos/capabilities/gaming.nix)
