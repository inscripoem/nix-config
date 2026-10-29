# Documentation

Start with [configuration architecture](nix-config-orchestration.md) for host
selection, module layout, and deployment commands.

| Topic | Guide |
|---|---|
| macOS user environment | [Home Manager on air](darwin-home-manager.md) |
| macOS package manager | [Lix ownership and recovery](darwin-lix.md) |
| macOS recovery generations | [Original migration recovery](nix-config-orchestration.md#original-migration-recovery) |
| Wyse 3040 hardware notes and DietPi layout | [Wyse 3040](wyse3040.md) |
| Encrypted credentials | [SOPS and age](secrets.md) |
| SSH authentication and Git signing | [1Password integration](ssh-agent.md) |
| Shell history | [Atuin and Zsh](atuin-zsh.md) |
| Running unpackaged software | [Ad-hoc software tools](adhoc-software.md) |
| Chinese input | [Rime](rime-nixos.md) |
| SiYuan packaging | [Workspace permissions](siyuan-workspace-perms.md) |
| Remote access before login | [Sunshine and SDDM](remote-desktop.md) |
| Desktop integration | [XDG portals](xdg-portal.md), [SDDM display variables](sddm-wayland-display.md) |
| Graphics | [NVIDIA](nvidia.md), [Intel Arc A380](intel-arc-a380.md) |
| Hardware stability | [H410 hard hangs](hard-hang-cstate.md), [Arc power measurements](intel-arc-a380-power.md) |

Write documentation in English. Keep current behavior, configuration rationale,
and useful operating steps; use links to source files instead of copying full
configurations. Record an observation's hardware or version limits, and keep
recovery information in the relevant operating guides. Detailed historical
rollout logs remain in Git history.
