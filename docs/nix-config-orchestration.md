# Configuration architecture

[outputs/default.nix](../outputs/default.nix) declares the hosts and assembles
NixOS, nix-darwin, Colmena, and deploy-rs outputs. Edit that table when adding a
host; the flake target name is independent of its network hostname.

## Hosts

| Target | Platform | System classes | Home Manager entry |
|---|---|---|---|
| `briefcase` | x86_64 Linux | `desktop`, `lan` | `home/hosts/briefcase.nix` |
| `vm` | x86_64 Linux | `vm`, `desktop`, `lan` | `home/hosts/vm.nix` |
| `wyse3040` | x86_64 Linux | `server`, `lan` | `home/hosts/wyse3040.nix` |
| `nutshell` | x86_64 Linux / WSL | `wsl` | `home/hosts/nutshell.nix` |
| `air` | Apple Silicon macOS | nix-darwin base | `home/hosts/air.nix` |

Only hosts with `deploy = true` enter the remote deployment outputs.

## NixOS modules

[lib/nixosModules.nix](../lib/nixosModules.nix) supplies the same module list to
NixOS and Colmena:

- `modules/nixos/base/`: shared system defaults, users, networking, Nix, and SSH.
- `modules/nixos/<class>/`: profiles selected by `spec.classes`.
- `hosts/<host>/`: hardware, disks, and host-specific overrides.
- `modules/nixos/capabilities/`: optional services selected through
  `modules.capabilities.<name>.enable`.
- Home Manager, SOPS, package overlays, and the host's extra modules/configuration.

Classes describe the machine or its environment. For example, `lan` enables
mDNS; Tailscale remains an optional capability because LAN membership does not
imply tailnet membership. `public` provides a stricter SSH baseline but is not
currently assigned to a host.

Capability modules are imported centrally and guard their configuration with
`lib.mkIf cfg.enable`. Multi-component capabilities can expose child switches.
Read each child's default: expensive AAGL launchers require explicit opt-in.

## Home Manager

| Entry | Scope |
|---|---|
| [home/core.nix](../home/core.nix) | Shared shell, Git, SSH, editors, and CLI tools |
| [home/tui.nix](../home/tui.nix) | Core plus terminal development tools |
| [home/desktop.nix](../home/desktop.nix) | TUI plus desktop applications and integration |
| [home/darwin/default.nix](../home/darwin/default.nix) | Core plus macOS adaptations |

NixOS imports [home/packs](../home/packs/default.nix) centrally. Host entries
select `packs.<name>.enable` and optional child switches for `ai`, `creative`,
`gaming`, and `toolchain`; they do not import individual packs again. Darwin's
assembly does not import these packs.

Both platforms use global packages, user packages, and `.backup` for conflicting
user files. Existing backup names must be resolved before activation.

## Darwin ownership

[lib/darwinModules.nix](../lib/darwinModules.nix) combines the host module,
Darwin base, and Home Manager. It passes `hostSpec` to HM and declares the
existing user's home directory.

On `air`:

- nix-darwin owns the system configuration and Lix package/daemon.
- Home Manager owns shared CLI tools and dotfiles; its Nix management stays off.
- [hosts/air/homebrew.nix](../hosts/air/homebrew.nix) declares Homebrew software,
  with activation updates, upgrades, and cleanup disabled.
- [home/hosts/air/legacy-shell.nix](../home/hosts/air/legacy-shell.nix) holds
  existing local tool initialization. New Macs must not inherit it.
- The Lix installer still owns the APFS store mount.

See [Home Manager](darwin-home-manager.md) and [Lix](darwin-lix.md) for operating
constraints, and the [migration record](../nix-darwin.plan) for recovery history.

## Adding configuration

For a NixOS host, add its host-table entry, hardware module, and HM entry.
Choose classes, capabilities, and packs there. A deployable host also needs
`hostname`, `sshUser`, and deployment tags. Remote-build clients need an
encrypted private key and a public key registered in `vars.builderClientKeys`;
see [secrets](secrets.md).

For macOS, add an entry to `darwinHosts`, a `hosts/<name>/default.nix`, and an HM
entry importing `../darwin`. Audit that machine's existing files and native
application paths before its first activation.

For a capability or pack, create its module and import it from the corresponding
`default.nix`. Add new `.nix` files to Git before evaluation: flakes ignore
untracked files. Evaluate every affected platform.

### Capability example

A system capability declares its option and guards the implementation. For
example, `modules/nixos/capabilities/locate.nix` could contain:

```nix
{ config, lib, ... }:
let cfg = config.modules.capabilities.locate;
in {
  options.modules.capabilities.locate.enable = lib.mkEnableOption "locate database";
  config = lib.mkIf cfg.enable {
    services.locate.enable = true;
  };
}
```

Import it in `modules/nixos/capabilities/default.nix`, then set
`extraConfig.modules.capabilities.locate.enable = true` in the target host's
entry in `outputs/default.nix`. Importing the module declares the option;
enabling it activates the service.

### Pack example

A pack groups user packages. For example, `home/packs/diagnostics.nix` could
make its child follow the parent by default:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.packs.diagnostics;
in {
  options.packs.diagnostics = {
    enable = lib.mkEnableOption "diagnostic tools";
    strace.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
    };
  };
  config.home.packages = lib.optional cfg.strace.enable pkgs.strace;
}
```

Import it in `home/packs/default.nix`, then set
`packs.diagnostics.enable = true` in a NixOS host's HM entry. Setting
`packs.diagnostics.strace.enable = false` excludes that child. In this pattern
the parent supplies a default; explicitly enabling a child still works when
the parent is off. Components that require deliberate opt-in can default to
`false` instead. This example uses a Linux package; Darwin does not import packs.

## Validation and deployment

Run from the repository:

```sh
# NixOS: one host, or all NixOS hosts when the argument is omitted.
just check briefcase

# Darwin: evaluate and preview build requirements.
nix eval --no-warn-dirty .#darwinConfigurations.air.config.system.build.toplevel.drvPath
nix build --no-link --dry-run .#darwinConfigurations.air.config.system.build.toplevel
```

Use the verification requirements in [AGENTS.md](../AGENTS.md) for configuration
changes. Evaluation does not prove that services or applications work at runtime.

### Darwin full build and first activation

These steps assume a working Nix/Lix installation and a host entry prepared
for this machine. Replace `air` with that entry's name when adding another Mac.
Complete the [HM file inventory](darwin-home-manager.md#restoring-or-onboarding-the-user-environment)
and, if taking over an installer-managed Lix, the
[Lix preparation](darwin-lix.md#before-transferring-ownership-on-another-installation)
before activation. The current configuration enables HM, Homebrew, and Lix;
it does not recreate the original system-only bootstrap stage.

After evaluation and dry-run, build the complete system without activating it:

```sh
nix build --no-warn-dirty --no-link --print-out-paths \
  .#darwinConfigurations.air.config.system.build.toplevel
```

Inspect the returned system's `activate` script, `etc` configuration, and HM
file changes. A dry-run lists build requirements; it does not perform this
build or validate the machine's existing-file collisions.

On a first installation, `darwin-rebuild` and `nhs` may not exist yet. The user
can run the rebuild tool from the revision pinned in `flake.lock`:

```sh
sudo -H nix run github:nix-darwin/nix-darwin/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48#darwin-rebuild -- switch --flake .#air
```

This command activates the system. Update the tool revision if the lock changes.
The first successful switch creates a generation; until then there is no earlier
nix-darwin generation to roll back to, so recovery relies on the prepared backups.

### Routine activation

After the first switch, `air` provides `nhs` in a fresh shell. Its explicit
equivalent, run from the repository, is:

```sh
sudo -H darwin-rebuild switch --flake .#air --show-trace
```

Other Macs need their own alias or can use that command with their target name.
The user runs `nhs` for local NixOS activation. Remote deployment uses
`just apply wyse3040`; initial installation uses the separate
[Wyse procedure](wyse3040-install.md). `just build-tarball nutshell` builds a
WSL import image; see the [justfile](../justfile) for its arguments.

At nix-darwin revision `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`,
`darwin-rebuild check` was observed to activate the system: the activation
script clears the wrapper's `checkActivation` environment variable. Use
`nix eval` and `nix build --dry-run` for non-activating checks at this revision.
