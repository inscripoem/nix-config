# Secrets management (SOPS + age)

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) to manage
host secrets (WiFi PSKs, future API tokens, etc.) in a way that:

1. Secrets are **encrypted at rest** in the git repo (age-encrypted
   YAML files under `secrets/`).
2. At NixOS activation, sops-nix decrypts them to `/run/secrets/`
   (tmpfs, root-readable only) — they never enter the Nix store.
3. **No plaintext** secret is ever committed to git.
4. Each host decrypts with its own SSH ed25519 host key (auto-derived
   to age format). No separate age key needs to be distributed to
   hosts — `/etc/ssh/ssh_host_ed25519_key` already lives there.

The encryption config lives in `.sops.yaml`; the secrets themselves in
`secrets/*.yaml`; the NixOS-side consumption in
`modules/nixos/base/wifi.nix`.

---

## 1. How the encryption keys work

SOPS uses [age](https://age-encryption.org/) encryption. `.sops.yaml`
lists **public** age keys (safe to commit to git). Anyone with the
matching **private** key can decrypt.

```
/etc/ssh/ssh_host_ed25519_key (SSH 私钥, chmod 600 root)
  → Ed25519 seed → SHA-512 → X25519 → age 私钥 (运行时解密用)
  → edwards25519 → montgomery → bech32 → age1... 公钥 (在 .sops.yaml 里)
```

Hosts have the private key automatically (it's their SSH host key).
The editor needs a **separate** age keypair — see §2.

**Three-key model.** `.sops.yaml` lists three recipients:

1. **Editor key** (daily use) — an independent age keypair generated via
   `age-keygen` at `~/.config/sops/age/keys.txt`. This is the key SOPS
   uses when you run `sops secrets/...` from the workstation.
2. **Recovery key** (last resort) — derived from a personal SSH ed25519
   key stored in 1Password via `ssh-to-age -i pub`. If the editor
   machine is lost, extract the SSH key from 1Password and run
   `ssh-to-age -private-key` to recover decryption ability. We do
   **not** use the 1Password SSH key as the daily editor key because
   the 1Password agent never exposes raw private key bytes to the
   filesystem, and SOPS needs a disk file.
3. **Host key** (auto-decrypt at activation) — derived from each
   host's `/etc/ssh/ssh_host_ed25519_key`. sops-nix reads it at
   activation time; no distribution needed.

---

## 2. One-time editor setup

```bash
# 1. Generate a brand-new age keypair (NOT linked to your SSH keys)
nix shell nixpkgs#age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# 2. Copy the PUBLIC key from the output (the age1... line) and add it
#    to .sops.yaml under `age:` in the `creation_rules` block.
#    (There's a placeholder comment in .sops.yaml for this.)

# 3. Tell SOPS where your private key lives:
#    Add this to your shell rc (.zshrc / .bashrc):
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# 4. Re-encrypt secrets so your editor key is a recipient:
sops updatekeys secrets/wifi.yaml

# 5. (Optional) Back up the age key to 1Password:
op document create ~/.config/sops/age/keys.txt --title "sops-nix age key"
```

---

## 3. Adding a new host to the recipients

This is how you onboard a future server or laptop.

**Phase 1 — First deployment (needs one-time wired network):**

```bash
# Deploy the machine while it's on wired Ethernet (or any working network).
# NixOS auto-generates an SSH host key on first boot.
nixos-rebuild switch --flake .#server --target-host root@new-host

# SSH in and retrieve the host's age public key:
ssh root@new-host "nix shell nixpkgs#ssh-to-age --command ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub"
# → age1...

# Add this public key to .sops.yaml under `age:`, then re-encrypt:
sops updatekeys secrets/wifi.yaml
git add .sops.yaml secrets/wifi.yaml && git commit -m "sops: add server host key"

# Re-deploy. Now the host can decrypt secrets — WiFi auto-connects
# on subsequent boots.
nixos-rebuild switch --flake .#server --target-host root@new-host
```

After Phase 1 the host has its age key registered and WiFi is
declaratively managed. All future rebuilds "just work" — the password
comes from the encrypted `secrets/wifi.yaml`.

**Alternative: one-shot with nixos-anywhere + pre-generated SSH host key**

If you don't want the two-phase deploy, generate an SSH host key pair
beforehand, put the public half in `.sops.yaml`, and pass the private
half to `nixos-anywhere --extra-files`. The first boot then already
has a known SSH host key and can decrypt WiFi immediately. See
[nixos-anywhere docs](https://github.com/nix-community/nixos-anywhere).

---

## 4. Editing a secrets file

```bash
sops secrets/wifi.yaml   # opens in $EDITOR; sops re-encrypts on save
```

Cleartext contents (visible only in the editor window):

```yaml
WIFI_SSID: HKHomeNet_5G
WIFI_PSK: your_actual_password
```

Git stores only the encrypted ciphertext.

---

## 5. Adding a new secret

1. Add the key to the YAML file:
   ```bash
   sops secrets/wifi.yaml   # or a new secrets/<name>.yaml
   ```

2. Declare it in a NixOS module:
   ```nix
   sops.secrets."MY_API_KEY" = {
     sopsFile = ../../../secrets/wifi.yaml;   # path from this module to the secrets file
     owner = "root";
     mode = "0400";
   };
   ```

3. Reference at runtime: `config.sops.secrets."MY_API_KEY".path`
   (points to `/run/secrets/MY_API_KEY`).

---

## 6. Current secrets

| File | Keys | Used by |
|------|------|---------|
| `secrets/wifi.yaml` | `WIFI_SSID`, `WIFI_PSK` | `modules/nixos/base/wifi.nix` → NetworkManager `ensureProfiles` |

---

## 7. Security model

- **`.sops.yaml`** — only public keys (safe to commit). Anyone can
  encrypt *for* a recipient; only the recipient can decrypt.
- **Host private key** (`/etc/ssh/ssh_host_ed25519_key`) — chmod 600
  root. The age private key is derived from it at runtime (SHA-512 of
  the ed25519 seed) and never written to disk. If an attacker gains
  root and reads this file, they can also read `/run/secrets/` — the
  two files share the same threat model. The sops-nix community
  considers SSH host keys an acceptable "master key" for host secrets.
- **Editor private key** (`~/.config/sops/age/keys.txt`) — never
  committed to git. Back up to 1Password. If lost, generate a new one
  and run `sops updatekeys`.

---

## 8. Why SOPS and not agenix

- **NetworkManager `ensureProfiles.environmentFiles` is designed for
  envsubst + environment-file consumption.** sops-nix's `sops.templates`
  generates exactly that format natively.
- **Multiple secrets in one file** — a YAML holds many keys. At our
  scale (a handful of secrets across 2-3 hosts) this is tidier than
  agenix's one-file-per-secret model.
- The trade-off is a slightly steeper initial learning curve
  (`.sops.yaml` rules, `sops.templates`). Once set up, adding a new
  secret or host costs 2-3 commands.