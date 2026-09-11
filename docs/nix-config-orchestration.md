# Nix Configuration Orchestration

This document records the design decisions, architecture, and target structure of the current cross-platform nix-config. It is the reference baseline for future extensions.

---

## 1. Host Model

Every host is defined by three orthogonal axes:

| Concept | Layer | Meaning | Example |
|---|---|---|---|
| **class** | NixOS system | Baseline profile of a machine or its network environment. Imported automatically based on `spec.classes`. | `desktop`, `server`, `vm`, `lan`, `public` |
| **capability** | NixOS system | Optional system service/daemon/kernel feature. Toggled per host via `options.modules.capabilities.<name>.enable`, with optional per-component sub-toggles. | `gaming`, `sunshine`, `docker`, `tailscale`, `smart` |
| **pack** | Home Manager | Optional bundle of user-level packages. Auto-imported into every NixOS host's HM via `hmBlock.sharedModules` (see [nixosModules.nix](../lib/nixosModules.nix)); each host only flips `packs.<name>.enable`, with per-package sub-toggles. Darwin Phase 2 does not import packs. | `creative`, `toolchain`, `ai`, `gaming` |

A host chooses a class stack, enables some capabilities, and selects some packs.

**Sub-toggle pattern** (used by both capabilities and packs with more than one distinct component):

```nix
options.<parent> = {
  enable = lib.mkEnableOption "...";
  <child>.enable = lib.mkOption {
    type = lib.types.bool;
    default = cfg.enable;   # child follows parent by default
  };
};
```

The parent switch stays as the coarse "on/off". Children default to the parent value so existing hosts keep working, but heavy or opt-in components (e.g. AAGL wine closures) explicitly override the default to `false` and require per-host opt-in.

---

## 2. Host Matrix

```nix
# outputs/default.nix
nixosHosts = {
  briefcase = {
    arch = "x86_64-linux";
    classes = [ "desktop" "lan" ];
    hmEntryPoint = ../home/hosts/briefcase.nix;
    deploy = false;
    extraModules = [ disko.nixosModules.disko /* niri */ ];
    extraConfig = {
      modules.capabilities.gaming = {
        enable = true;
        # AAGL launchers each pull a large wine closure, so they are
        # opt-in per host rather than following the parent enable.
        aagl.anime-game-launcher.enable = true;
        aagl.honkers-railway-launcher.enable = true;
        # aagl.sleepy-launcher.enable = true;  # Zenless Zone Zero
      };
      modules.capabilities.sunshine.enable = true;
      modules.capabilities."1password".enable = true;
      modules.capabilities.smart.enable = true;
      modules.capabilities.deploy-tools.enable = true;
      modules.capabilities.remote-builder.enable = true;
      modules.capabilities.tailscale.enable = true;
    };
  };
  vm = {
    arch = "x86_64-linux";
    classes = [ "vm" "desktop" "lan" ];
    hmEntryPoint = ../home/hosts/vm.nix;
    deploy = false;
    extraConfig = { modules.capabilities.tailscale.enable = true; };
  };
  wyse3040 = {
    arch = "x86_64-linux";
    classes = [ "server" "lan" ];
    hmEntryPoint = ../home/hosts/wyse3040.nix;
    deploy = true;
    hostname = "wyse3040.local";
    sshUser = "root";
    tags = [ "home" ];
    extraModules = [ disko.nixosModules.disko ];
    extraConfig = {
      modules.capabilities.tailscale.enable = true;
      modules.capabilities.sdcard.enable = true;
      modules.capabilities.impermanence.enable = true;
      modules.capabilities.remote-build-client.enable = true;
      modules.capabilities.docker.enable = true;
    };
  };
};

darwinHosts = {
  air = {
    arch = "aarch64-darwin";
    hostModule = ../hosts/air;
    hmEntryPoint = ../home/hosts/air.nix;
  };
};
```

---

## 3. System Architecture

### 3.1 Class Modules

Classes are directories under `modules/nixos/`. `lib/nixosModules.nix` imports `modules/nixos/<class>/default.nix` for every class in the host spec.

| Class | Dir | Responsibility |
|---|---|---|
| `desktop` | `modules/nixos/desktop/` | Plasma/SDDM, audio, fonts, xdg-portal, printing, input-method, keyring, browser defaults, X11 forwarding |
| `server` | `modules/nixos/server/` | Stable kernel, less aggressive panic timeout |
| `vm` | `modules/nixos/vm/` | VMware guest support |
| `lan` | `modules/nixos/lan/` | mDNS/avahi for `.local` resolution; assumes a trusted local network |
| `public` | `modules/nixos/public/` | SSH hardening, fail2ban, restrictive firewall (reserved, not deployed) |

`desktop`, `server`, and `vm` answer "what kind of machine is this?". `lan` and `public` answer "what network environment is it in?". They are orthogonal mixins.

**Design rationale — why not put avahi/tailscale in capabilities?**
- **avahi** is a pure LAN assumption: every machine on the local network benefits from `.local` resolution, and a public server should not publish itself. It belongs to the `lan` class.
- **tailscale** is a VPN overlay. A LAN machine might intentionally not join the tailnet (e.g., an isolated IoT bridge), so it remains a per-host capability.
This split keeps the `lan` class meaningful while preserving per-host choice for the VPN.

### 3.2 Capability Modules

Capabilities live in `modules/nixos/capabilities/`. Each module declares:

```nix
{ config, lib, ... }:
let cfg = config.modules.capabilities.gaming;
in {
  options.modules.capabilities.gaming.enable = lib.mkEnableOption "...";
  config = lib.mkIf cfg.enable { /* real config */ };
}
```

All capability modules are imported unconditionally by `lib/nixosModules.nix`; only hosts that set `modules.capabilities.<name>.enable = true` activate them.

| Capability | Responsibility |
|---|---|
| `gaming` | System-level gaming stack. Sub-toggles: `steam`, `gamemode`, `waydroid` (+ `waydroid.helper`), `aagl.{anime-game-launcher,honkers-railway-launcher,sleepy-launcher}` (each AAGL launcher is opt-in) |
| `sunshine` | Moonlight/Sunshine streaming (SDDM greeter + user service handoff) |
| `1password` | 1Password system integration (CLI, GUI, browser bridge) |
| `remote-builder` | Accepts remote Nix builds (nix-builder user + authorized_keys) |
| `tailscale` | Tailscale daemon |
| `sdcard` | SD/eMMC wear mitigation (tmpfs, zram, GC, fstrim) |
| `impermanence` | Ephemeral root + /persist whitelist (btrfs rollback on boot) |
| `remote-build-client` | Distributes Nix builds to vars.builders |
| `smart` | Disk health surveillance (smartmontools, nvme-cli) |
| `deploy-tools` | Deployment CLIs (colmena, deploy-rs) |
| `docker` | Docker daemon, docker-compose, docker group; persists state when impermanence is active |

### 3.3 Shared Module List (`lib/nixosModules.nix`)

Both `lib/mkNixos.nix` and `outputs/colmena.nix` call `lib/nixosModules.nix` to produce the common module list for a given host spec. It handles:

- Class directory imports from `spec.classes`
- Unconditional capability module imports
- Base modules (`modules/nixos/base/`)
- sops-nix and home-manager wiring
- Home Manager block
- Optional `spec.extraConfig` and `spec.extraModules`

### 3.4 Base Module

`modules/nixos/base/default.nix` imports: nix-daemon, nixpkgs, i18n, users, networking (NetworkManager only), wifi, shells, nh, kernel (latest + panic defaults via `mkDefault`), packages, state, ssh.

### 3.5 SSH Strategy

- **Base** (`base/ssh.nix`): permissive — `PasswordAuthentication = true`, `PermitRootLogin = "prohibit-password"`, convenience for local/trusted hosts.
- **desktop class** (`desktop/ssh-x11.nix`): `X11Forwarding = true` for GUI hosts.
- **public class** (reserved): SSH hardening (`PasswordAuthentication = false`, `PermitRootLogin = "no"`), fail2ban.

### 3.6 Colmena

`outputs/colmena.nix` reuses `lib/nixosModules.nix` and adds `deployment.*` per node. No module list duplication.

### 3.7 Builder Keys (sops-nix)

Remote-build client SSH keys are generated on the deployer machine and stored in sops:

- Private key → `secrets/builder.yaml` (SOPS-encrypted, auto-decrypted to `/persist/root/.ssh/builder_ed25519` at activation).
- Public key → `keys/<host>-builder-ed25519.pub`, referenced by `vars.builderClientKeys`.

Each remote-build client gets its own keypair. No manual `ssh-keygen` on target hosts.

### 3.8 nix-darwin bootstrap

`lib/mkDarwin.nix` and `lib/darwinModules.nix` mirror the existing NixOS
assembly pattern. Each entry in `darwinHosts` becomes a
`darwinConfigurations.<name>` target, while the flake target remains separate
from the machine's macOS hostname.

Phase 1 was deployed to `air` on 2026-09-06. That generation is system-only:

- `nix.enable = false` leaves the existing Lix installation, daemon, build
  users, and `/etc/nix/nix.conf` externally managed.
- Homebrew management and Home Manager are not enabled.
- No hostname or macOS defaults are declared.
- nix-darwin establishes its system generation, global Zsh integration, and
  its default system Bash integration while preserving the currently enabled
  Touch ID sudo behavior.

The original `/etc/pam.d/sudo_local` is retained as
`/etc/pam.d/sudo_local.before-nix-darwin`. The Phase 1 generation is the
rollback anchor for the Home Manager migration in Phase 2.

Phase 2 now wires Home Manager through `spec.hmEntryPoint`, with the host
name passed as `hostSpec.name`. It uses global pkgs, user packages, and
non-overwriting `.backup` files. The existing macOS user's home directory is
declared explicitly. Homebrew inventory remains Phase 3; the Lix ownership
decision remains a separate optional phase. Both the system and Darwin HM
explicitly disable Nix management. Darwin also omits the Fish-triggered
`mandb` index until the pinned Fish manuals are compatible with its parser;
ordinary man pages remain available.

Phase 2 was activated on `air` on 2026-09-07 as `system-2-link`. The automated
audit and 2026-09-11 live acceptance confirmed that the system matches the
current flake output, all 24 enabled HM file targets are linked, expected
backups remain available, and Atuin, editor, HTTPS/TLS, GitHub SSH, private SSH,
and OrbStack SSH behavior work. Homebrew, Lix, and existing language toolchain
ownership remain outside nix-darwin as designed. Phase 1 generation 1 remains
the rollback anchor. The formal whole-file commit provides the native-signing
check and repository boundary. See
[Darwin Home Manager migration](darwin-home-manager.md).

---

## 4. Home Manager Architecture

### 4.1 Entry Points

| Entry | Imports | Used by |
|---|---|---|
| `home/core.nix` | `home/core/` | NixOS and Darwin shared user configuration |
| `home/tui.nix` | `home/core/` + `home/tui/` | Terminal-oriented dev hosts |
| `home/desktop.nix` | `home/core/` + `home/tui/` + `home/desktop/` | GUI hosts |
| `home/darwin/default.nix` | `home/core.nix` + platform adaptations | Darwin hosts |

### 4.2 Layer Contents

| Layer | Contents |
|---|---|
| `core/` | git, ssh, shell (zsh/fish/starship/bat/yazi/atuin/tealdeer/fzf/eza/zoxide/carapace/direnv), CLI editors (nvim/helix), basic CLI tools (ripgrep/fd/jq/yq-go/duf/dust/htop/bottom/lazygit/gping), compression, fastfetch, nix-output-monitor, nix-index |
| `tui/` | pueue (task queue), tokei (line counter) |
| `desktop/` | GUI terminals (alacritty/wezterm/zellij), desktop env (plasma/niri/deskflow/wl-clipboard), GUI editors (vscode/zed/trae-cn), browsers (vivaldi/zen), media (vlc), productivity (libreoffice/localsend/siyuan), social (qq), 1password GUI, glances, rime, cc-switch |
| `darwin/` | Core entry, native 1Password Git signer/SSH socket, Git configuration target and Zsh dot-directory adaptation; no host-specific PATH or tool initialization |

`home/hosts/air/legacy-shell.nix` is the strict boundary for the existing
machine's PATH, Brew/Zerobrew, certificate selection, NVM/Bun/Go, Cargo/Rye,
Proto/Moon, local CLI paths, OrbStack shell integration, OMZ plugins, and
aliases. New Macs must not inherit these settings through the generic Darwin
layer. A later tool migration removes the corresponding legacy initialization
when a Nix module takes ownership; Phase 2 does not replace language toolchains.

`air` imports core only, not tui or desktop. Pueue is not enabled, and the
host disables tealdeer's scheduled updater while keeping on-use updates.

### 4.3 Packs

Packs are optional user-level package sets. Each pack is a home-manager module declaring `options.packs.<name>.{enable, <child>.enable}`. All pack files are aggregated in `home/packs/default.nix` and auto-injected into every NixOS host's HM via `hmBlock.sharedModules` in [nixosModules.nix](../lib/nixosModules.nix). NixOS hosts do **not** import pack files themselves; they only flip `packs.<name>.enable = true;` in `home/hosts/<name>.nix`. Child toggles default to the parent value and can be flipped off individually to trim the closure. Darwin Phase 2 deliberately does not enable this package-bundle layer.

| Pack | Sub-toggles → contents |
|---|---|
| `creative` | `ardour`, `audacity`, `blender`, `gimp`, `godot` (`godot_4`), `zrythm` |
| `toolchain` | `node` (bun/nodejs_22/pnpm/yarn), `python` (uv), `rust` (rustup), `build` (just/devenv) |
| `ai` | `aichat`, `opencode` (+ `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS`), `antigravity-cli`, `ck`, `claude-code`, `codex`, `rtk`, `zcode` (+ xdg `x-scheme-handler/zcode` association) |
| `gaming` | `lutris`, `maa` (maa-assistant-arknights + maa-cli, same upstream software), `ww-manager` |

### 4.4 Per-host HM Entries

NixOS entries pick a base layer (`core.nix` / `tui.nix` / `desktop.nix`) and
flip the packs they want. `home/hosts/air.nix` instead imports `../darwin`
and its own `air/legacy-shell.nix`, preserves host-specific Git/SSH settings,
and requires the externally restored private SSH fragment before HM links files.

```nix
# home/hosts/briefcase.nix
{
  imports = [ ../desktop.nix ];
  packs.ai.enable = true;
  packs.creative.enable = true;
  packs.gaming.enable = true;
  packs.toolchain.enable = true;

  # Uninstall trae-cn and zcode on briefcase only; vm keeps trae-cn.
  desktop.editors-gui.traeCn.enable = false;
  packs.ai.zcode.enable = false;
}

# home/hosts/vm.nix        — desktop only, no packs
# home/hosts/wyse3040.nix  — tui + ai + toolchain
```

---

## 5. Directory Layout

```
nix-config/
├── flake.nix
├── outputs/
│   ├── default.nix        # Host table + nixosConfigurations
│   ├── colmena.nix        # Reuses lib/nixosModules.nix
│   └── deploy.nix
├── lib/
│   ├── default.nix
│   ├── mkNixos.nix        # Host → nixosSystem
│   ├── nixosModules.nix   # NixOS module list (classes + caps + base)
│   ├── mkDarwin.nix       # Host → darwinSystem
│   └── darwinModules.nix  # Darwin system + Home Manager assembly
├── vars/
│   └── default.nix        # username, builders, builderClientKeys
├── hosts/
│   ├── briefcase/
│   ├── air/               # macOS host module
│   ├── vm/
│   └── wyse3040/
├── modules/nixos/
│   ├── base/              # nix-daemon, networking, ssh, kernel, wifi, etc.
│   ├── desktop/           # Plasma, audio, xdg-portal, printing, input-method, niri
│   ├── server/            # Stable kernel
│   ├── vm/                # VMware guest
│   ├── lan/               # avahi/mDNS
│   ├── public/            # SSH hardening (reserved)
│   └── capabilities/      # Optional system services (see §3.2)
├── modules/darwin/
│   └── base/              # conservative nix-darwin system baseline
├── home/
│   ├── core/              # All hosts (shell, git, ssh, editors, CLI tools)
│   ├── tui/               # Dev hosts (pueue, tokei)
│   ├── desktop/           # GUI hosts (terminals, browsers, desktop env, apps)
│   ├── darwin/            # Shared Darwin platform adaptations, no local PATH
│   ├── packs/             # Optional bundles (creative, toolchain, ai, gaming)
│   ├── hosts/             # Per-host entries, including air.nix
│   │   └── air/           # air-only legacy shell/tool initialization
│   ├── core.nix
│   ├── tui.nix
│   └── desktop.nix
├── pkgs/
├── secrets/               # SOPS-encrypted (wifi.yaml, builder.yaml)
├── keys/                  # Public keys
├── docs/
└── scripts/
```

---

## 6. Adding a New Host

For NixOS:

1. Add entry to `nixosHosts` in `outputs/default.nix`: choose `classes`, enable `capabilities` via `extraConfig`
2. Create `hosts/<name>/` with `default.nix` + `hardware-configuration.nix`
3. Create `home/hosts/<name>.nix` to select HM entry point + packs
4. If deployable: set `deploy = true`, `hostname`, `sshUser`, `tags`
5. Run `nix eval` for the new host
6. If remote-build client: generate keypair, add to `secrets/builder.yaml` and `keys/`

For macOS:

1. Add `arch`, `hostModule`, and `hmEntryPoint` to `darwinHosts`.
2. Create `hosts/<name>/default.nix`; macOS needs no NixOS hardware file.
3. Create `home/hosts/<name>.nix`, importing `../darwin`. Do not reuse air's
   legacy shell module; audit the new machine's own settings and collisions.
4. Evaluate `darwinConfigurations.<name>`, run a dry-run, build, and review
   generated files before manually switching.

---

## 7. Adding a New Capability

1. Create `modules/nixos/capabilities/<name>.nix`:
   ```nix
   { config, lib, ... }:
   let cfg = config.modules.capabilities.<name>;
   in {
     options.modules.capabilities.<name>.enable = lib.mkEnableOption "...";
     config = lib.mkIf cfg.enable { /* implementation */ };
   }
   ```
2. Add it to the imports in `modules/nixos/capabilities/default.nix`
3. Enable per host via `extraConfig.modules.capabilities.<name>.enable = true`

For capabilities that bundle several independent components, follow the sub-toggle pattern from §1 (parent enable + per-component `<child>.enable` with `default = cfg.enable`). Components with a heavy closure or narrow use-case should override the default to `false` so they stay opt-in.

---

## 8. Adding a New Pack

1. Create `home/packs/<name>.nix` as a home-manager module:
   ```nix
   { config, lib, pkgs, ... }:
   let cfg = config.packs.<name>;
   in {
     options.packs.<name> = {
       enable = lib.mkEnableOption "...";
       <child>.enable = lib.mkOption {
         type = lib.types.bool;
         default = cfg.enable;
       };
     };
     config.home.packages =
       lib.optional cfg.<child>.enable pkgs.<child>;
   }
   ```
2. Add the file to `imports` in [home/packs/default.nix](../home/packs/default.nix). This aggregator is auto-injected into every host's HM via `hmBlock.sharedModules` in [nixosModules.nix](../lib/nixosModules.nix), so no host-side `imports` change is needed.
3. In the target host's `home/hosts/<name>.nix`, flip `packs.<name>.enable = true;`. Flip individual `<child>.enable` off to trim the closure.

---

## 9. Deployment

- **Local NixOS hosts** (briefcase, vm): `sudo nixos-rebuild switch --flake .#<host>`
- **Remote hosts** (wyse3040): `just apply wyse3040` (colmena) or `deploy .#wyse3040` (deploy-rs)
- **Darwin bootstrap switch**: `sudo -H nix run github:nix-darwin/nix-darwin/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48#darwin-rebuild -- switch --flake .#<host>`
- **Darwin later switches**: `sudo -H darwin-rebuild switch --flake .#<host>`
- **NixOS pre-deploy check**: `nix eval --no-warn-dirty .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
- **Darwin pre-deploy check**: `nix eval --no-warn-dirty .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath`

The first successful Darwin switch creates the rollback anchor for Phase 2.
Before that point there is no previous nix-darwin generation, so Phase 1 keeps
Lix, Homebrew, hostname, macOS defaults, and user dotfiles outside its
ownership boundary.

At the pinned nix-darwin revision, `darwin-rebuild check` was observed to run
the activation script instead of remaining non-mutating: the wrapper's
`checkActivation` environment variable is cleared by the generated activation
script's `/usr/bin/env -i` shebang. Use `nix eval` and `nix build --dry-run` as
the non-mutating gates for this revision; do not rely on `check` as a dry run.

---

**Document version**: v2.7 (2026-09-11)
**Status**: Current (`air` Phase 2 active and accepted)

### Changelog

- **v2.7**: Recorded completed live SSH acceptance, kept external language toolchains outside Phase 2 ownership, and defined the formal signed commit as the repository boundary.
- **v2.6**: Recorded the successful `air` Phase 2 activation, live HM ownership, automated post-switch audit, partial interactive acceptance, external Proto status, and retained Phase 1 rollback anchor.
- **v2.5**: Added Darwin Home Manager assembly, shared/platform/host ownership boundaries, air-only transitional shell setup, private SSH preparation, and the Phase 2 migration guide. Language toolchain migration stays separate.
- **v2.4**: Recorded the successful `air` Phase 1 deployment, first system generation, PAM backup, default system Bash ownership, and the pinned revision's mutating `darwin-rebuild check` behavior.
- **v2.3**: Added the `air` nix-darwin target with a system-only first phase. Existing Lix, Homebrew, hostname, macOS defaults, and user dotfiles remain externally managed until their explicitly reviewed follow-up phases.
- **v2.2**: Pack files are now auto-imported into every host's HM via `hmBlock.sharedModules` in [nixosModules.nix](../lib/nixosModules.nix), aggregated by `home/packs/default.nix`. Each host only writes `packs.<name>.enable = true;`, mirroring the capability layer. `gaming` pack module-ized with 3 sub-toggles: `lutris`, `maa` (maa-assistant-arknights + maa-cli, same upstream software), `ww-manager`. Fixed wyse3040 pack drift (was importing `toolchain`/`ai` without ever enabling them).
- **v2.1**: Capabilities and packs now use a shared sub-toggle pattern. `gaming` capability split into `steam` / `gamemode` / `waydroid[.helper]` / `aagl.*` (each AAGL launcher opt-in). Userland gaming packages (MAA, ww-manager) moved to the `gaming` pack. Packs (`creative`, `toolchain`, `ai`, `gaming`) converted from bare imports to modules with per-package sub-toggles; `toolchain` further grouped as `node` / `python` / `rust` / `build`. Added §8 "Adding a New Pack".
- **v2.0**: Rewritten to reflect class/capability/pack model. Added class modules, capability modules, shared module list, SSH strategy, builder keys via sops, HM packs, per-host HM entries
- **v1.2**: Replaced parallel HM class layering with progressive entry points + optional packs
- **v1.1**: Clarified generator purity, class auto-import, HM class layer
- **v1.0**: Initial document
