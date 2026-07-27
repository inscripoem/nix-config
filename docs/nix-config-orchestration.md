# Nix Configuration Orchestration

This document records the design decisions, architecture, and target structure of the current nix-config. It is the reference baseline for future extensions.

---

## 1. Host Model

Every host is defined by three orthogonal axes:

| Concept | Layer | Meaning | Example |
|---|---|---|---|
| **class** | NixOS system | Baseline profile of a machine or its network environment. Imported automatically based on `spec.classes`. | `desktop`, `server`, `vm`, `lan`, `public` |
| **capability** | NixOS system | Optional system service/daemon/kernel feature. Toggled per host via `options.modules.capabilities.<name>.enable`. | `gaming`, `sunshine`, `docker`, `tailscale`, `smart` |
| **pack** | Home Manager | Optional bundle of user-level packages. Imported explicitly in `home/hosts/<name>.nix`, one per line. | `creative`, `toolchain`, `ai`, `gaming` |

A host chooses a class stack, enables some capabilities, and selects some packs.

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
      modules.capabilities.gaming.enable = true;
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
```

---

## 3. NixOS System Architecture

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
| `gaming` | Steam, Proton-GE, gamemode |
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

---

## 4. Home Manager Architecture

### 4.1 Entry Points

| Entry | Imports | Used by |
|---|---|---|
| `home/core.nix` | `home/core/` | All hosts |
| `home/tui.nix` | `home/core/` + `home/tui/` | Terminal-oriented dev hosts |
| `home/desktop.nix` | `home/core/` + `home/tui/` + `home/desktop/` | GUI hosts |

### 4.2 Layer Contents

| Layer | Contents |
|---|---|
| `core/` | git, ssh, shell (zsh/fish/starship/bat/yazi/atuin/tealdeer/fzf/eza/zoxide/carapace/direnv), CLI editors (nvim/helix), basic CLI tools (ripgrep/fd/jq/yq-go/duf/dust/htop/bottom/lazygit/gping), compression, fastfetch, nix-output-monitor, nix-index |
| `tui/` | pueue (task queue), tokei (line counter) |
| `desktop/` | GUI terminals (alacritty/wezterm/zellij), desktop env (plasma/niri/deskflow/wl-clipboard), GUI editors (vscode/zed/trae-cn), browsers (vivaldi/zen), media (vlc), productivity (libreoffice/localsend/siyuan), social (qq), 1password GUI, glances, rime, cc-switch |

### 4.3 Packs

Packs are optional user-level package sets, imported in `home/hosts/<name>.nix`.

| Pack | Contents |
|---|---|
| `creative` | ardour, audacity, blender, gimp, godot_4, zrythm |
| `toolchain` | bun, nodejs_22, pnpm, yarn, uv, rustup, just, devenv |
| `ai` | aichat, opencode, antigravity-cli, ck, claude-code, rtk + `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS` |
| `gaming` | lutris |

### 4.4 Per-host HM Entries

```nix
# home/hosts/briefcase.nix  —  desktop + creative + toolchain + ai + gaming
# home/hosts/vm.nix         —  desktop only
# home/hosts/wyse3040.nix   —  tui + toolchain + ai
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
│   └── nixosModules.nix   # Shared module list (classes + caps + base)
├── vars/
│   └── default.nix        # username, builders, builderClientKeys
├── hosts/
│   ├── briefcase/
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
├── home/
│   ├── core/              # All hosts (shell, git, ssh, editors, CLI tools)
│   ├── tui/               # Dev hosts (pueue, tokei)
│   ├── desktop/           # GUI hosts (terminals, browsers, desktop env, apps)
│   ├── packs/             # Optional bundles (creative, toolchain, ai, gaming)
│   ├── hosts/             # Per-host entry point selection
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

1. Add entry to `nixosHosts` in `outputs/default.nix`: choose `classes`, enable `capabilities` via `extraConfig`
2. Create `hosts/<name>/` with `default.nix` + `hardware-configuration.nix`
3. Create `home/hosts/<name>.nix` to select HM entry point + packs
4. If deployable: set `deploy = true`, `hostname`, `sshUser`, `tags`
5. Run `nix eval` for the new host
6. If remote-build client: generate keypair, add to `secrets/builder.yaml` and `keys/`

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

---

## 8. Deployment

- **Local hosts** (briefcase, vm): `sudo nixos-rebuild switch --flake .#<host>`
- **Remote hosts** (wyse3040): `just apply wyse3040` (colmena) or `deploy .#wyse3040` (deploy-rs)
- **Pre-deploy check**: `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`

---

**Document version**: v2.0 (2026-07-13)  
**Status**: Current (reflects class/capability/pack model, P1-P4 complete, P5 complete)

### Changelog

- **v2.0**: Rewritten to reflect class/capability/pack model. Added class modules, capability modules, shared module list, SSH strategy, builder keys via sops, HM packs, per-host HM entries
- **v1.2**: Replaced parallel HM class layering with progressive entry points + optional packs
- **v1.1**: Clarified generator purity, class auto-import, HM class layer
- **v1.0**: Initial document
