# nix-config

Personal NixOS and nix-darwin configuration, managed as a single flake.

## Hosts

| Host | Platform | Description |
| --- | --- | --- |
| `briefcase` | NixOS | Primary workstation, Niri + DMS desktop |
| `air` | macOS | Laptop managed with nix-darwin |
| `vm` | NixOS | Virtual machine guest |
| `nutshell` | NixOS | Windows Subsystem for Linux instance |

Host declarations live in `outputs/default.nix`.

## Layout

| Path | Purpose |
| --- | --- |
| `outputs/default.nix` | Host declarations and flake outputs |
| `modules/nixos/` | System defaults, classes, and optional capabilities |
| `modules/darwin/` | Shared nix-darwin configuration |
| `hosts/<host>/` | Per-host hardware and entry points |
| `home/<group>/` | Home Manager modules |
| `pkgs/` | Locally packaged software |
| `docs/` | Long-form rationale; start at [docs/README.md](docs/README.md) |

## Usage

```bash
# NixOS hosts
sudo nixos-rebuild switch --flake .#briefcase

# Darwin host
darwin-rebuild switch --flake .#air
```

See [configuration architecture](docs/nix-config-orchestration.md) for host
selection, module layout, and deployment commands.

## Secrets

No plaintext secret is committed to this repository. Credentials are encrypted
with [SOPS](https://github.com/getsops/sops) and
[age](https://github.com/FiloSottile/age); decryption happens on the target
host at activation time using per-host keys that are not stored here. See
[docs/secrets.md](docs/secrets.md) for the key roles and workflow.

## License

Released under the [MIT License](LICENSE). This is a personal configuration
shared for reference; interfaces may change without notice.
