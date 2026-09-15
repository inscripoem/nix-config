# SSH and Git signing with 1Password

SSH authentication and Git signing use 1Password, but have separate entry
points. The shared configuration selects the provider; platform and host
modules supply its integration.

The original problem was having to run `ssh-add` after each reboot. Since
1Password was already in use, its agent provided encrypted key storage, device
sync, and request approval without adding another key-management system.
Importing the existing key also preserved its fingerprint. This choice depends
on access to the desktop app and vault; keep the recovery path below available.

## 1. Configuration sources

| Source | Responsibility |
|---|---|
| [home/core/ssh.nix](../home/core/ssh.nix) | SSH settings and GitHub over port 443 |
| [home/core/git.nix](../home/core/git.nix) | Signing key, `op-ssh-sign`, and allowed signers |
| [1Password capability](../modules/nixos/capabilities/1password.nix) | NixOS CLI/GUI, polkit, and browser bridge |
| [Desktop integration](../home/desktop/1password.nix) | Linux socket, GCR masks, vault allowlist, and GUI autostart |
| [Darwin integration](../home/darwin/default.nix) | Native app signer and Group Containers socket |

Host selection lives in [outputs/default.nix](../outputs/default.nix).
`briefcase` enables the system capability. `vm` imports desktop HM integration
but does not enable that capability. `nutshell` uses the TUI/WSL entry; its
WSL HM module currently adds no agent bridge. Importing shared SSH/Git policy
alone does not provide a running agent on every host.

## 2. Agent selection

`IdentityAgent` directs OpenSSH to the chosen socket; `SSH_AUTH_SOCK` supports
other agent clients, including `ssh-add`.

- Linux desktop: `~/.1password/agent.sock`.
- Darwin: the native app's Group Containers socket, set in the Darwin module.
  Its path contains spaces and is quoted in the generated SSH configuration.

1Password must be running, signed in, and configured to use its SSH agent.
The Linux allowlist selects the vault named `加密密钥`; this is a literal vault
name, not a translated label. Other accounts need their own selection.

## 3. GCR conflict on Linux

The desktop module masks `gcr-ssh-agent.socket` and `gcr-ssh-agent.service`
with empty user unit files. GCR can start through systemd socket activation,
so disabling an old XDG autostart entry is insufficient. GNOME Keyring stays
enabled for the Secret Service API used by applications.

After activating a mask change, log out and back in to discard any previously
running agent. Check with:

```sh
systemctl --user status gcr-ssh-agent.socket gcr-ssh-agent.service
printf '%s\n' "$SSH_AUTH_SOCK"
ssh-add -l
```

The GCR units should report masked, and the listed keys should match 1Password.

## 4. SSH configuration

Edit `programs.ssh.settings` in the appropriate host module. For example:

```nix
programs.ssh.settings."example" = {
  HostName = "example.net";
  User = "deploy";
};
```

OpenSSH uses the first obtained value for most options. Inspect generated order
and effective settings when adding overlapping host patterns:

```sh
ssh -G github.com | rg '^(hostname|port|user|identityagent) '
```

GitHub should resolve to `ssh.github.com`, port 443, user `git`. Evaluation
checks Nix option types; it cannot confirm a socket path exists or a server
accepts the key.

On `air`, OrbStack owns its included configuration and private hosts live in
`~/.ssh/config.local`. See [Darwin Home Manager](darwin-home-manager.md).

## 5. First setup

Before activation, preserve existing SSH configuration and GUI-generated
`agent.toml` files, checking that backup names are unused. Keep private host
settings outside the public repository.

After the user runs `nhs`, sign in to 1Password and enable its SSH agent in
Settings → Developer. Import the existing SSH key if its fingerprint must
remain unchanged, and make sure the configured vault exposes it.

Test `ssh-add -l` and `ssh -T git@github.com`. GitHub's successful authentication
message still exits with status 1 because it provides no shell. Retain recovery
material until authentication and signing both work.

## 6. Git signing

Git invokes `op-ssh-sign` directly using the public key in
[keys/ssh-ed25519.pub](../keys/ssh-ed25519.pub). It does not discover its signing
key through `ssh-add`. Darwin selects the helper inside the native app.

```sh
git config --show-origin --get gpg.ssh.program
git config --get user.signingkey
git log -1 --show-signature
```

The last command checks an existing commit, not whether a new signature can be
created. Test creation during the next intended signed commit. The matching
private key must be available to the native app.

## 7. Temporary recovery

If a trusted local copy of the private key is available, restrict it to mode
0600 and bypass agent selection for one SSH command:

```sh
ssh -o IdentityAgent=none -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 example
```

This retains host routing from SSH configuration. It does not repair Git
signing: a local signing fallback also needs an OpenSSH signer and the local
key path. Do not assume another agent starts automatically when 1Password is
unavailable.

## 8. Troubleshooting

| Symptom | Check |
|---|---|
| Socket missing | App running, account signed in, SSH agent enabled |
| Cannot connect to agent | Effective `SSH_AUTH_SOCK`; start a fresh login shell |
| Unexpected keys | Socket selection and stale GCR process on Linux |
| No identities | Configured vault/items and account access |
| Too many authentication failures | Select a specific public key with `IdentityFile` and `IdentitiesOnly` |
| Signing fails | Effective `gpg.ssh.program`, public signing key, app access to its private half |
| Browser stays locked | Native app integration and browser allowlist |

## 9. Linux app integration

The system capability installs the browser helper and polkit policy.
`/etc/1password/custom_allowed_browsers` includes `vivaldi-bin`; add other
browser process names there when needed, then restart the browser after
activation. Sandboxed browser packages may need a different integration path.

System-authentication unlock is enabled in the app's Security settings;
fingerprint unlock also requires working hardware and fprintd. The desktop
module starts the GUI with `--silent` and manages the SSH vault allowlist.
