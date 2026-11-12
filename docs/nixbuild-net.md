# Remote builds on nixbuild.net

[nixbuild.net](https://docs.nixbuild.net/) runs Nix derivations on hardware the
service operates. The local nix-daemon ships the closure over SSH, the remote
side builds it and returns the results.

The builder is registered but remote scheduling stays off by default: the
capability keeps `nix.distributedBuilds` false, so nixpkgs writes an empty
`builders` value into nix.conf and overrides Nix's built-in default
`builders = @/etc/nix/machines`. Plain switches (`nhs`) build locally only and
spend none of the account's CPU budget; remote work is opt-in per invocation
through the aliases in `home/core/shell.nix`.

## Quota

- Every account gets 25 CPU hours once. When they are spent, builds stop until
  billing is activated.
- With billing active the account receives up to 25 free CPU hours per month;
  beyond that the rate is 0.12 EUR per CPU hour, excluding VAT.
- A build request that can be served from an existing result costs no CPU time,
  and substituted paths never reach the builder. Derivation inputs do: do not
  route builds carrying private data through a third-party builder.

The admin shell is `ssh eu.nixbuild.net`; `usage`, `builds`, `ssh-keys` and
`billing` report and manage the account.

## Repository wiring

| Piece | Location |
|---|---|
| Capability module | [nixbuild-net.nix](../modules/nixos/capabilities/nixbuild-net.nix) |
| Encrypted key | `secrets/nixbuild.yaml` → `nixbuildnet_builder_ed25519` |
| Host switch | `modules.capabilities.nixbuild-net.enable` (enabled on briefcase) |
| Per-switch override | `nhsr` (remote-first), `nhsc` (strict remote), `nhsf` (local-first retry) |

The module writes root's SSH client configuration for `eu.nixbuild.net`
(`ServerAliveInterval 60`, the decrypted `IdentityFile`), the service host key
into `knownHosts`, and one `x86_64-linux` build machine entry with
`maxJobs 100` and the features the service advertises (`benchmark`,
`big-parallel`, `ca-derivations`, `kvm`, `nixos-test`).

Builds print `on 'ssh://eu.nixbuild.net'` when a derivation runs remotely.
Enabling the capability on another host is a one-line change in
`outputs/default.nix`; all hosts share the account, so the CPU budget does not
grow with the number of clients.

## Scheduling

| Alias | Runs | When the builder cannot take a job |
|---|---|---|
| `nhs` | local only | not applicable (default) |
| `nhsr` | nixbuild.net first | local jobs build it (unreachable, saturated, or the derivation needs a system/feature the service lacks) |
| `nhsc` | nixbuild.net only (`--max-jobs 0`) | the switch fails with `local builds are disabled (max-jobs = 0)` instead of silently loading this machine |
| `nhsf` | local first | the switch is retried through `nhsr` (e.g. after an OOM kill) |

Nix schedules in one direction only: the build hook ranks the entries of
`/etc/nix/machines` by load and speed factor and hands the job to one of them,
declining to local when none can take it. A busy local machine never pushes
work to a builder, and local load is invisible to that comparison.
`preferLocalBuild` derivations stay local in every mode.

Darwin hosts have the capability disabled, so `/etc/nix/machines` is absent
there: `nhsr` and `nhsf` degrade to local builds, while `nhsc` fails because
nothing can take the job.

## Key handling

nixbuild.net is used with two independent Ed25519 keys; the account holds both.

- **Daemon key** — passwordless, stored in `secrets/nixbuild.yaml` and
  decrypted to `/run/secrets` at activation as `root:root`, mode `0400`.
  nix-daemon reads it through the system SSH config, and a changed value
  restarts `nix-daemon.service` (see [secrets](secrets.md)). It is never
  readable by the interactive user.
- **Admin key** — used only for `ssh eu.nixbuild.net`. It lives in the
  1Password vault `加密密钥` and is served by the 1Password SSH agent, which
  is the session-wide `IdentityAgent` (see [ssh-agent](ssh-agent.md)). No
  private key is stored in `$HOME`.

Do not share one file between root and the user: OpenSSH rejects a key with
group/other permission bits when the reader owns it, so a group-readable copy
breaks the daemon, while a `0400` root copy is unreadable by the user.

Rotate either key by adding the new public half first (`ssh-keys add` in the
admin shell), verifying a login, then replacing the SOPS value or the
1Password item, and finally removing the old key from the account.

## Boundaries

The service builds `i686-linux`, `x86_64-linux`, `aarch64-linux` and
`armv7l-linux`. Darwin targets (`air`) must build locally, on the community
`darwin-build-box`, or on another Mac.

Verify one-off builds with the service explicitly before blaming the
configuration:

```sh
sudo ssh -o BatchMode=yes eu.nixbuild.net true
nix build -L --builders 'ssh://eu.nixbuild.net x86_64-linux - 100 1 benchmark,big-parallel,ca-derivations,kvm,nixos-test' .#nixosConfigurations.briefcase.config.system.build.toplevel
```
