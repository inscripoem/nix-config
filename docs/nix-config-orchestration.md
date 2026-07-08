# Nix Configuration Orchestration Principles

This document records the design decisions, requirements, target structure, and migration path for the current nix-config reorganization. It serves as the reference baseline for future extensions.

---

## 1. Background and Requirements

### 1.1 Current State

- **Host count**: 2 (`briefcase` primary machine, `vm` test virtual machine)
- **Platform**: NixOS only (x86_64-linux)
- **Deployment**: Local `nixos-rebuild`, no remote deployment
- **Config scale**: `configuration.nix` is a 248-line monolith; `home/` has 53 files across 15 groups

### 1.2 Target State

Manage **multiple heterogeneous machines** spanning different platforms, architectures, and use cases:

| Host | Platform | Architecture | Purpose | Special Requirements |
|---|---|---|---|---|
| `briefcase` | NixOS | x86_64-linux | Primary dev + gaming | disko, NVIDIA, desktop environment |
| `vm` | NixOS | x86_64-linux | Testing | VMware guest tools |
| `wsl-dev` (reserved) | NixOS (WSL) | x86_64-linux | Dev only, no GUI | nixos-wsl, no desktop |
| `darwin-*` (reserved) | macOS | aarch64-darwin | Package mgmt + system settings | nix-darwin |
| `srv-*` (reserved) | NixOS | x86_64 / aarch64 | Servers | Immutable system, remote deploy via deploy-rs/colmena |

### 1.3 Core Requirements

1. **Unified multi-host management**: All machines derived from a single declaration table; adding a host means editing the table + adding a directory
2. **Heterogeneous support**: Different platforms (NixOS / macOS), architectures (x86_64 / aarch64), use cases (desktop / server / WSL)
3. **Remote deployment**: Servers deployed in bulk via colmena; critical deployments use deploy-rs's magic rollback
4. **Extensible**: Reserve interfaces for darwin, WSL, server so future additions don't require restructuring
5. **Maintainable**: Eliminate redundant files, unify naming, separate concerns

---

## 2. Current Pain Points

### 2.1 Structural Issues

| Issue | Location | Impact |
|---|---|---|
| Home-manager wiring block duplicated verbatim between two hosts | flake.nix 53-67 vs 79-94 | Adding a host requires copy-paste, error-prone |
| 15 files are just `home.packages = [ pkgs.xxx ]` with no configuration | browsers/vivaldi.nix, toolchains/*, ai/*, etc. | File bloat; agonizing over whether to create a new file per package |
| Inconsistent naming for "package-only" files | `misc.nix` / `packages.nix` / `default.nix` / `<tool>.nix` mixed | Mental model confusion |
| Custom derivations (siyuan/trae/cc-switch/glances) embedded in home modules | home/productivity/siyuan.nix, etc. | Cannot be reused across hosts or at system level |
| `configuration.nix` is a 248-line monolith mixing 7 domains | configuration.nix | Changing a setting requires hunting through a large file |
| No darwin host slot, no server profile, no deploy outlet | flake.nix outputs | Adding a new platform requires restructuring |

### 2.2 Extensibility Issues

- Adding a third host: must edit flake.nix outputs and copy the home-manager wiring block
- Adding macOS: no nix-darwin generator; must hand-write darwinConfigurations
- Adding servers: no deploy-rs/colmena outlet; must hand-write deploy.nodes
- Adding WSL: no nixos-wsl class module; must hand-write specialization

---

## 3. Design Principles

### 3.1 Single Source of Truth

- **Host declaration table**: All host metadata (architecture, class, deploy config) centralized in `vars/` or at the top of `outputs/nixos.nix`
- **User identity**: Username, email, SSH public keys, stateVersion centralized in `vars/default.nix`, passed via `specialArgs`
- **Custom packages**: All custom derivations centralized in `pkgs/`, exposed as `pkgs.<name>` via overlay

### 3.2 File Existence Criterion

**Hard rule**: Should a home module file exist as a standalone file?

| Situation | Handling |
|---|---|
| Only `home.packages = [ pkgs.X ]`, no configuration | Fold into the group's `default.nix` as a flat `home.packages` list; **do not create a separate file** |
| `programs.X = { enable = true; settings = ... }` with actual configuration | Keep as a separate file |
| `systemd.user.services` / custom wrapper / custom derivation patch | Keep as a separate file |

**Benefit**: `home/` file count drops from 53 to ~30, and "only create a file when there's real configuration" becomes an enforceable rule.

### 3.3 Host Declaration Table Driven

All outputs (`nixosConfigurations`, `darwinConfigurations`, `colmena`, `deploy.nodes`) derived from a single host declaration table:

```nix
nixosHosts = {
  briefcase = { class = [ "desktop" ]; arch = "x86_64-linux"; deploy = false; };
  vm        = { class = [ "vm" ];     arch = "x86_64-linux"; deploy = false; };
  # Reserved:
  # wsl-dev  = { class = [ "wsl" ];  arch = "x86_64-linux"; deploy = true; };
  # srv-a    = { class = [ "server" "impermanence" ]; arch = "x86_64-linux";  deploy = true; tags = ["prod"]; };
};
```

The generator `lib/mkNixos.nix` accepts a host spec and produces `nixosSystem { ... }`, with built-in:
- `specialArgs = { inherit inputs vars; }`
- Always imports `modules/nixos/base`
- Imports the corresponding profile directory per class (see §3.4)
- Imports `hosts/<name>/` per host
- Integrates home-manager via `hmEntryPoint` parameter (see §3.4)

**Generators must be generic**: `mkNixos` must not hardcode any class-specific modules (e.g. plasma-manager, zen-browser). Class-specific NixOS modules and HM sharedModules are auto-imported based on `spec.classes`, keeping the generator pure and reusable across desktop, server, WSL, and VM hosts.

### 3.4 Layered Composition

#### NixOS System Modules

NixOS system modules compose in three layers:

```
base (shared across all NixOS hosts)
  ↓
class (desktop / server / wsl / vm) — auto-imported by mkNixos based on spec.classes
  ↓
host (per-host specifics)
```

- `modules/nixos/base/`: nix-daemon, i18n, users, networking, ssh, nh
- `modules/nixos/desktop/`: SDDM/Plasma/niri, audio, fonts, xdg-portal, printing
- `modules/nixos/server/`: SSH hardening, firewall, monitoring, docker/containers (reserved)
- `modules/nixos/wsl/`: nixos-wsl wrapper (reserved)
- `modules/nixos/vm/`: VM guest integration

#### Home-Manager Modules: Progressive Entry Points

Home-manager modules use a **progressive entry point** system with 3 layers + optional packs:

```
core (all hosts: shell, git, ssh, CLI editors, basic tools)
  ↓
tui (dev hosts: core + toolchains, AI CLI tools, task queues)
  ↓
desktop (GUI hosts: tui + GUI apps, browsers, terminals, desktop environment)
```

**Entry point files** (each imports all layers below it):

- `home/core.nix` → imports `./core` (servers, minimal hosts)
- `home/tui.nix` → imports `./core` + `./tui` (WSL, dev servers)
- `home/desktop.nix` → imports `./core` + `./tui` + `./desktop` (desktop/laptop)

**Layer contents**:

| Layer | Contents | Hosts |
|---|---|---|
| `core/` | shell (bash/zsh/fish/starship/bat/yazi/atuin/tealdeer/fzf/eza/zoxide/carapace/direnv), git (SSH signing + delta), ssh (config), CLI editors (nvim/helix), basic CLI tools (ripgrep/fd/jq/yq-go/duf/dust/htop/bottom/lazygit/gping), compression tools (zip/xz/unzip/p7zip), fastfetch, nix-output-monitor | All hosts |
| `tui/` | toolchains (devenv/tokei/bun/nodejs/pnpm/yarn/uv/rustup), AI CLI tools (aichat/opencode/claude-code/antigravity-cli/rtk/ck), pueue (task queue) | Dev hosts (WSL + desktop + dev servers) |
| `desktop/` | GUI terminals (alacritty/wezterm/zellij), desktop environment (plasma/niri/deskflow/wl-clipboard), GUI editors (vscode/zed/trae-cn), browsers (vivaldi/zen), media (vlc), productivity (libreoffice/localsend/siyuan), social (qq), compat (bottles), gaming (lutris), 1password (GUI), glances (GPU monitoring) | Desktop/laptop only |

**Optional packs** (per-host selection):

| Pack | Contents | Description |
|---|---|---|
| `creative` | zrythm, ardour, audacity, gimp, godot_4, blender | Music + video + graphics production |

Packs are imported per-host in `home/hosts/<name>.nix`.

**Per-host overrides**: `home/hosts/<name>.nix` selects the entry point + packs + any host-specific extras:

```nix
# home/hosts/briefcase.nix
{ imports = [ ../desktop.nix ../packs/creative.nix ]; }

# home/hosts/vm.nix
{ imports = [ ../tui.nix ]; }
```

**mkNixos integration**: `mkNixos` accepts an `hmEntryPoint` parameter (defaults to `../home/desktop.nix`):

```nix
# lib/mkNixos.nix
{ ..., hmEntryPoint ? ../home/desktop.nix, ... }:
{
  home-manager.users.${vars.username} = import hmEntryPoint;
}

# outputs/default.nix
nixosHosts = {
  briefcase = { hmEntryPoint = ../home/desktop.nix; ... };
  vm        = { hmEntryPoint = ../home/tui.nix;    ... };
};
```

**Design rationale**: 3 layers is the community gold standard (validated by ryan4yin, TophC7, xander-4x, and 30+ other configs). 4+ layers are unnecessary for personal configs with <10 hosts. When a host needs something that doesn't fit the 3 layers, use packs or per-host overrides instead of adding a new layer.

### 3.5 Deployment Tool Choice

**colmena + deploy-rs coexist**, both derived from the same host declaration table:

| Scenario | Tool | Rationale |
|---|---|---|
| Routine multi-node deploy | `colmena apply --on @prod` | Parallel, tags, native secret management |
| Risky single-node deploy (kernel changes, first deploy to new machine) | `deploy .#srv-a` | Magic rollback safety net |
| Build + diff | `colmena build` / `nix store diff-closures` | Either works |

**~30 lines of glue code**, no technical debt. This pattern is community-validated (colmena issue #60, multiple discourse threads).

**Pitfall**: If colmena uses `nodes.<name>` to cross-reference other host configurations, that part cannot be directly reused in `nixosConfigurations` — the fix is to keep cross-references only at the colmena layer and keep base modules pure.

---

## 4. Target Structure

```
nix-config/
├── flake.nix              # Thin: only declares inputs + outputs = inputs: import ./outputs inputs
├── outputs/
│   ├── default.nix        # Merges all faces: nixosConfigurations / darwinConfigurations / colmena / deploy / packages / devShells
│   ├── nixos.nix         # Generates nixosConfigurations from host declaration table
│   ├── darwin.nix        # Generates darwinConfigurations (empty initially, interface reserved)
│   ├── colmena.nix       # Derives colmena nodes from host table
│   └── deploy.nix        # Derives deploy-rs nodes from host table
├── lib/
│   ├── default.nix       # Small utilities: autoImport / exe / mkForceIf
│   ├── mkNixos.nix       # NixOS host generator (encapsulates specialArgs / home-manager wiring)
│   ├── mkDarwin.nix      # nix-darwin generator
│   └── mkColmena.nix     # Colmena node wrapper
├── vars/
│   └── default.nix       # username / fullName / email / sshKeys / stateVersion centralized
├── hosts/
│   ├── briefcase/        # Current hardware/briefcase/* moved here
│   ├── vm/               # Current hardware/vm/*
│   ├── wsl/              # Reserved
│   ├── darwin/           # Reserved
│   └── servers/          # Reserved
├── modules/
│   ├── nixos/            # NixOS system-level modules split by domain
│   │   ├── base/         # Across all NixOS hosts: nix-daemon, i18n, users, networking, ssh, nh
│   │   ├── desktop/      # SDDM/Plasma/niri, audio, fonts, xdg-portal, printing
│   │   ├── server/       # SSH hardening, firewall, monitoring, docker/containers (reserved)
│   │   ├── wsl/          # nixos-wsl wrapper (reserved)
│   │   ├── vm/           # VM guest integration
│   │   ├── gaming.nix    # Current system/gaming.nix
│   │   ├── tailscale.nix # Current system/tailscale.nix
│   │   └── 1password.nix # Current system/1password.nix
│   ├── darwin/           # Reserved: nix-darwin modules by domain
│   └── shared/           # Reserved: cross-platform shared
├── home/
│   ├── core/              # Entry point 1: all hosts (shell, git, ssh, CLI editors, basic tools)
│   ├── tui/               # Entry point 2: dev hosts (toolchains, AI CLI, task queues)
│   ├── desktop/           # Entry point 3: GUI hosts (browsers, terminals, desktop env, GUI apps)
│   ├── packs/             # Optional capability packs (creative, etc.)
│   ├── core.nix           # Entry file: imports = [ ./core ]
│   ├── tui.nix            # Entry file: imports = [ ./core ./tui ]
│   ├── desktop.nix        # Entry file: imports = [ ./core ./tui ./desktop ]
│   └── hosts/             # Per-host overrides (select entry point + packs + extras)
├── pkgs/
│   ├── default.nix       # Overlay collector
│   ├── siyuan.nix
│   ├── trae-cn.nix
│   ├── cc-switch.nix
│   └── glances.nix
├── docs/                 # Unchanged
├── keys/                 # Unchanged
├── scripts/              # Unchanged
├── installer/            # Unchanged (separate flake)
└── AGENTS.md
```

**Handling of `configuration.nix`**: Remove entirely, replaced by `modules/nixos/base/`. Rationale: keeping a thin shell leaves a "two sources of truth" ambiguity — future changes to a setting will agonize over whether to write it in `configuration.nix` or `modules/nixos/base/xxx.nix`.

---

## 5. Migration Phases

Each phase is independently verifiable and independently committable (per AGENTS.md commit conventions). Each phase ends with:

```bash
nix eval --no-warn-dirty .#nixosConfigurations.briefcase.config.system.build.toplevel.drvPath
```

Package-related changes use `nix build --dry-run`.

### P1: Extract pkgs

- Move 4 custom derivations (siyuan/trae/cc-switch/glances) from home modules to `pkgs/`
- Create `pkgs/default.nix` as overlay collector
- Home modules switch to `pkgs.siyuan`, etc.
- **Risk**: Low. **Rollback**: Restore home files

### P2: lib + vars + outputs skeleton

- Create `lib/`, `vars/`, `outputs/`
- Change flake.nix to one-line outputs: `outputs = inputs: import ./outputs inputs;`
- Don't delete old `configuration.nix`; new outputs temporarily 100% equivalent to old
- **Minimal skeleton only**: `outputs/default.nix` is a single file (not yet split into `nixos.nix` / `darwin.nix` / `colmena.nix` / `deploy.nix`); `lib/default.nix` is a placeholder (no `autoImport` etc. yet); class auto-import is not implemented (that's P5)
- **Risk**: Medium (flake evaluation can break). **Rollback**: `git restore flake.nix`

### P3: Split configuration.nix

- Split `configuration.nix`'s 7 domains into `modules/nixos/base` and `modules/nixos/desktop`
- Old file becomes `imports = [ ./modules/nixos/base/default.nix ./modules/nixos/desktop/default.nix ]` or is deleted entirely
- **Risk**: Medium. **Rollback**: Restore old configuration.nix

### P4: Clean up home

- Merge 15 trivial files per file existence criterion
- Unify naming
- **Risk**: Low. **Rollback**: git restore specific files

### P5: Reorganize host classes + home entry points

- Split briefcase/vm content into `hosts/<name>/` + class modules
- New briefcase/vm generated via `mkNixos` with `hmEntryPoint` parameter
- Move old `hardware/<host>/` to `hosts/<host>/`
- Reorganize `home/` into progressive entry points: `core/` → `tui/` → `desktop/`
- Create entry files: `core.nix`, `tui.nix`, `desktop.nix`
- Create `packs/creative.nix` for optional creative tools
- Create `home/hosts/<name>.nix` for per-host entry point selection
- Move 1password from core to desktop (GUI only)
- Move nvim/helix from current editors to core (CLI editors needed everywhere)
- Move gping to core, cc-switch to desktop
- **Risk**: Medium. **Rollback**: Restore paths and revert flake

### P6: colmena + deploy-rs outlet

- `outputs/{colmena,deploy}.nix` derived from host table
- Add `colmena` and `deploy-rs` as flake inputs
- Currently briefcase/vm don't expose nodes (`deploy = false`), but `colmena eval` and `deploy .#checks` should not error
- **Risk**: Low. **Rollback**: Remove colmena/deploy-rs inputs

### P7: Reserve empty skeletons

- Add empty directories: `modules/darwin/`, `modules/nixos/{wsl,server}/`, `hosts/{wsl,darwin,servers}/`
- Include placeholder `default.nix` + "to be implemented" comments
- Don't wire into host table
- **Risk**: None. **Rollback**: Delete empty directories

---

## 6. References

### 6.1 Reference Repositories

| Repository | Key Insights |
|---|---|
| [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) | `flake.nix` has only one-line outputs; `lib/` contains generators; `vars/` centralizes user/SSH/networking; `outputs/<arch>/src/<host>.nix` one file per host |
| [sodiboo/system](https://github.com/sodiboo/system) | `*.mod.nix` + `zipAttrs` auto-layers by profile (`universal` → `personal` → `host`), cleanest grouping abstraction for heterogeneous hosts |
| [gvolpe/nix-config](https://github.com/gvolpe/nix-config) | `hosts = [...]` list-driven generation; `builders.mkNixos` / `mkHome` injected via overlay |
| [Ruixi-rebirth/flakes](https://github.com/Ruixi-rebirth/flakes) | `me.nix` centralizes user identity; `flake-parts` keeps flake.nix thin; WSL uses `nixos-wsl` replacing boot/hardware |
| [j4ger/nix-config](https://github.com/j4ger/nix-config) | `lib/autoImport` auto-scans .nix files + subdirectories containing default.nix |
| [JonathanReeve/dotfiles](https://github.com/JonathanReeve/dotfiles) | Anti-pattern: `home.nix` 500+ lines, `environment.systemPackages` 150-line giant list |

### 6.2 Deployment Tool Research

- **colmena**: v0.4.0 (2026-05), actively maintained, hive model, tags, parallel deployment, native secret management, **no magic rollback**
- **deploy-rs**: Still active as of 2026-06 (PR #381), has magic rollback, but ~100 open issues, magic rollback can false-positive on network jitter
- **Community reconciliation pattern**: Derive both `colmena` and `deploy.nodes` from the same `hosts` table, ~30 lines of glue, no off-the-shelf bridge tool
- **New tool panix**: 2026-04 beta, may mature by end of 2026, not adopting now

---

## 7. Future Extension Checklist

When adding a new host:

1. Add a row to the host declaration table in `outputs/default.nix`
2. Set `hmEntryPoint` to the appropriate entry point (`core.nix` / `tui.nix` / `desktop.nix`)
3. Create `hosts/<name>/` directory with `default.nix` + `hardware-configuration.nix`
4. Create `home/hosts/<name>.nix` to select entry point + packs + per-host extras
5. If deployable, set `deploy = true` + `hostname` + `sshUser` + `tags`
6. Run `nix eval` to verify
7. Run `colmena eval` or `deploy .#checks` to verify deploy config

When adding a new platform (e.g. macOS):

1. Add modules in `modules/darwin/`
2. Add generation logic in `outputs/darwin.nix`
3. Add darwin hosts to the declaration table (`system = "darwin"`)
4. Run `nix eval .#darwinConfigurations.<name>.system` to verify

---

**Document version**: v1.2 (2026-07-08)  
**Status**: In progress (P1-P4 done, P5 pending)

### Changelog

- **v1.2**: Replaced parallel HM class layering with progressive entry points (core → tui → desktop) + optional packs; added hmEntryPoint parameter to mkNixos; added package mapping table; updated P5 scope
- **v1.1**: Clarified generator purity (§3.3), class auto-import mechanism (§3.4), HM class layer (§3.4), P2 minimal scope (§5), stateVersion in vars (§3.1)
- **v1.0**: Initial document
