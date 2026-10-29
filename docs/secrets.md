# Secrets with SOPS and age

[.sops.yaml](../.sops.yaml) defines recipients for encrypted YAML files in
[secrets](../secrets). NixOS uses sops-nix to decrypt declared secrets at
activation. Plaintext is read through runtime paths, not embedded in Nix store
files. The module's `owner`, `mode`, and optional `path` control access.

## 1. Key roles

- **Editor key:** a local age key at `~/.config/sops/age/keys.txt` for routine
  editing.
- **Recovery key:** derived from a personal Ed25519 key stored in 1Password.
  Recovery requires access to the private key bytes; the SSH agent alone
  cannot decrypt SOPS files.
- **Host keys:** each registered machine decrypts using its SSH Ed25519 host
  key. Preserve that key across reinstalls or update the SOPS recipients.

The current creation rule shares one recipient list across `secrets/*.yaml`.
Adding a recipient to a file grants access to every secret in that file.

## 2. Editor setup

For a new editor key, create the directory and generate the key only if the
key file does not already exist:

```sh
install -d -m 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Use `nix shell nixpkgs#age nixpkgs#sops` if the tools are unavailable. Add the
public `age1...` recipient to `.sops.yaml`. The shared shell configuration
already exports `SOPS_AGE_KEY_FILE`; in an unmanaged shell use:

```sh
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

An existing recipient must rewrap each affected encrypted file:

```sh
sops updatekeys secrets/wifi.yaml
sops updatekeys secrets/builder.yaml
```

A newly generated key cannot decrypt old files until this is done. Back up the
editor key privately. If it is lost, use a surviving recipient or the recovery
key to grant access to its replacement.

### Recovering a lost editor key

Use `nix shell nixpkgs#ssh-to-age nixpkgs#age nixpkgs#sops` if needed. Create a
private directory outside the checkout:

```sh
sops_recovery_dir=$(mktemp -d "$HOME/sops-recovery.XXXXXX")
```

From a device where 1Password is accessible, export the registered recovery
SSH item's Ed25519 private key to `$sops_recovery_dir/id_ed25519`. Convert it
to an age identity; the subshell restricts permissions and refuses to overwrite
an existing output:

```sh
(
  set -euC
  umask 077
  chmod 600 "$sops_recovery_dir/id_ed25519"
  ssh-to-age -private-key -i "$sops_recovery_dir/id_ed25519" \
    > "$sops_recovery_dir/age-key.txt"
)
age-keygen -y "$sops_recovery_dir/age-key.txt"
```

Stop if conversion fails. Compare the printed public recipient with the recovery
entry in `.sops.yaml`. Generate a replacement editor key using the setup above
(preserve any existing key file first), and replace the lost editor recipient
in `.sops.yaml`, keeping the recovery and host recipients. Rewrap both files
using the recovery identity:

```sh
SOPS_AGE_KEY_FILE="$sops_recovery_dir/age-key.txt" sops updatekeys secrets/wifi.yaml
SOPS_AGE_KEY_FILE="$sops_recovery_dir/age-key.txt" sops updatekeys secrets/builder.yaml
```

Verify each file with the replacement editor key without printing plaintext:

```sh
SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" sops --decrypt secrets/wifi.yaml > /dev/null
SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" sops --decrypt secrets/builder.yaml > /dev/null
```

After both succeed and the replacement key has a private backup, remove the
temporary exported SSH key and converted age identity. Keep the recovery item
in 1Password for future use.

## 3. Registering a host

Obtain the host's age public key over a trusted connection:

```sh
ssh root@HOST 'ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub'
```

Add it to `.sops.yaml`, then run `sops updatekeys` for the required files using
an existing recipient. On a new installation, either deploy a baseline that
does not require undecryptable secrets, or provision the registered host key
with `nixos-anywhere --extra-files`. Wired networking alone does not fix a
SOPS activation failure.

## 4. Editing and adding secrets

```sh
sops secrets/wifi.yaml
```

SOPS re-encrypts on save. Add a new key in the encrypted editor, declare it in
the consuming module, and reference `config.sops.secrets.<name>.path` at
runtime. Use `sops.templates` when a service needs a generated configuration
containing several secrets.

For example, after adding `MY_API_KEY` with SOPS to `secrets/example.yaml`, a
module under `modules/nixos/capabilities/` can declare:

```nix
{ ... }:
{
  sops.secrets.MY_API_KEY = {
    sopsFile = ../../../secrets/example.yaml;
    owner = "root";
    mode = "0400";
  };
}
```

The consumer uses `config.sops.secrets.MY_API_KEY.path` at runtime. Adjust the
owner for the consuming service and the relative source path for the module's
location. Add the new encrypted file to Git before evaluating the flake. Do
not use `builtins.readFile` to put plaintext into an evaluated Nix string.
The [WiFi module](../modules/nixos/capabilities/wifi-profiles.nix) is a complete
example of a `sops.templates` environment file consumed by a service.

## 5. Current consumers

| File | Keys | Consumer |
|---|---|---|
| `secrets/wifi.yaml` | `wifi_HKHomeNet_5G_ssid`, `wifi_HKHomeNet_5G_psk`, `wifi_HKHomeNet_ssid`, `wifi_HKHomeNet_psk` | [WiFi profiles capability](../modules/nixos/capabilities/wifi-profiles.nix) |

`secrets/builder.yaml` is kept as an archive. Its `wyse3040_builder_ed25519`
key lost its consumer when the wyse3040 host left the flake on 2026-10-29;
the orphan entry is harmless and no module reads the file anymore.

WiFi profiles are opt-in through `modules.capabilities.wifi-profiles.enable`.
They use a root-only environment template with NetworkManager system
connections, so networking does not depend on a desktop keyring unlock.
`briefcase` enables them; fixed-Ethernet hosts do not need them.

A remote-build client's public key belongs in `keys/` and
`vars.builderClientKeys`; its private half belongs in the encrypted builder
file. Deploy both the client secret and builder authorization.

SOPS is used here because grouped YAML keys and runtime templates fit the WiFi
and builder configuration. Keep plaintext keys and decrypted files out of Git.
