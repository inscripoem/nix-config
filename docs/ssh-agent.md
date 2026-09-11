# SSH agent on `briefcase`

How SSH key authentication is wired up on this machine, and why each
piece is configured the way it is. The **configuration** lives in:

- `system/1password.nix` (imported by `configuration.nix`) —
  system-level glue: `programs._1password{,-gui}` (installs the GUI,
  the SSH agent socket at `~/.1password/agent.sock`, the CLI `op`,
  the polkit policy that lets the GUI talk to the CLI, and the setuid
  wrapper for browser integration), plus
  `environment.etc."1password/custom_allowed_browsers"` to opt vivaldi
  into the native-messaging bridge.
- `home/secrets/1password.nix` — user-level glue:
  `home.sessionVariables.SSH_AUTH_SOCK = ~/.1password/agent.sock`, the
  systemd-user mask for `gcr-ssh-agent.{socket,service}` so the
  gnome-keyring SSH agent does not race with 1Password, and the
  1Password agent key allowlist
  (`~/.config/1Password/ssh/agent.toml`).
- `home/core/ssh.nix` — `programs.ssh` (renders `~/.ssh/config`); pins
  `IdentityAgent` for every host and declares the `github.com:443`
  fall-through. The Linux agent path is a default that a platform module
  can override; installing/configuring the provider remains separate.
- `home/core/git.nix` — wires `gpg.ssh.program` to `op-ssh-sign` so
  `git commit -S` signs through 1Password directly.

On `briefcase`, the entire `~/.ssh/config` is Nix-managed; see section 4 for
how to add or temporarily override a host.

Darwin `air` reuses the shared Git/SSH policy, while `home/darwin/default.nix`
selects the native 1Password app and its quoted Group Containers socket path.
It sets both `IdentityAgent` and `SSH_AUTH_SOCK` from one value; it does not
install another agent or import the Linux systemd configuration. The host
entry preserves OrbStack's generated Include and a private, out-of-store
`~/.ssh/config.local`. Git signing still calls `op-ssh-sign` directly,
independently of SSH transport authentication. See
[Darwin Home Manager migration](darwin-home-manager.md) for preparation,
private-host ownership, and rollback.

---

## 1. Why 1Password and not the obvious alternatives

The pain point: `ssh-add` had to be run by hand after every reboot,
because no agent on the system was persisting unlocked keys across
sessions.

Options considered:

| Option | Persists keys | Cost | Why rejected |
|---|---|---|---|
| `services.openssh.startAgent` + `ssh-add` in shell rc | manual | free | every shell startup runs `ssh-add`; if the key has a passphrase the first interactive shell of the session blocks on the prompt. With no passphrase you're trusting on-disk plaintext to fs perms only. |
| `gnome-keyring` SSH component (`gcr-ssh-agent`, what was running before) | no (GCR 4+) | free | GCR ≥ 4 dropped persistence — keys are forgotten the moment the session ends. Combined with a no-passphrase key, the keyring never even prompts to store it. This is the regression we are working around. |
| `gpg-agent --enable-ssh-support` | yes, with passphrase cache | medium | requires moving SSH keys into a GPG identity. Heavy machinery for one use case, and the cache timeout still loses keys eventually. |
| YubiKey / FIDO2 (`ssh-keygen -t ed25519-sk`) | hardware | ~$50, one-time | best security, no subscription, but requires the key to be physically present for every operation. Out of scope for a desktop primary machine where the user is already an active 1Password subscriber. |
| **1Password agent (chosen)** | yes (encrypted vault, synced) | already paid | private key lives in the 1Password vault, never on disk after migration; same key usable on every device the user signs into 1Password from; per-request authorization configurable. |

Decision rule: since 1Password is already a paid subscription used for
the rest of the user's secrets, adding SSH to it gets vault sync,
optional Touch ID / system-auth approval, and gradual-migration support
"for free", while solving the persistence problem at the agent level
instead of by papering over it in shell rc.

---

## 2. Three layers, and what each one buys

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: 1Password agent.toml (nix → home/secrets/1password.nix)│
│   ~/.config/1Password/ssh/agent.toml                            │
│   Allowlists "加密密钥" vault. Without it 1Password offers      │
│   keys from Personal/Private/Employee only -- this vault is     │
│   custom, so ssh-add -l would otherwise be empty.               │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: ~/.ssh/config (per-host; nix → home/core/ssh.nix)      │
│   `Host * IdentityAgent ~/.1password/agent.sock`                │
│   Most direct way to tell OpenSSH which agent to talk to.       │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: $SSH_AUTH_SOCK (nix → home/secrets/1password.nix)      │
│   Catches non-OpenSSH consumers (ssh-add, rsync, scp            │
│   wrappers, IDE Git integrations). Git's own SSH signing        │
│   now bypasses this via op-ssh-sign -- see §6.                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                  ~/.1password/agent.sock
                              │
                  socket only exists while
                  1Password desktop app is
                  running AND unlocked
```

Layer 1 alone is enough for almost everything; Layer 2 is the official
recommendation because `IdentityAgent` in `~/.ssh/config` takes
precedence over `$SSH_AUTH_SOCK` and is per-host, so gradual migration
is possible. Layer 3 is **required** on this account because the SSH
keys live in a custom vault; without it the agent silently has zero
keys to offer.

---

## 3. The gnome-keyring conflict (why `home/secrets/1password.nix` masks
two systemd user units)

`services.gnome.gnome-keyring.enable = true` (we keep it for libsecret
apps) does **not** just install the keyring daemon. As of `gcr` 4.x it
also pulls in two user-level systemd units:

```
/etc/systemd/user/gcr-ssh-agent.socket
/etc/systemd/user/gcr-ssh-agent.service
/etc/systemd/user/sockets.target.wants/gcr-ssh-agent.socket
/etc/systemd/user/default.target.wants/gcr-ssh-agent.service
```

Both are wanted unconditionally by `sockets.target` / `default.target`,
so they come up automatically with every login. The agent listens on
`/run/user/<uid>/gcr/ssh` and *will* publish that path into the systemd
user environment as `SSH_AUTH_SOCK` if nothing else has claimed the
variable yet.

### What we tried first (and why it failed)

A previous version of this file recommended shadowing
`/etc/xdg/autostart/gnome-keyring-ssh.desktop` with a `Hidden=true` copy
under `~/.config/autostart/`. That advice is parroted on a lot of
"disable gnome-keyring SSH" blog posts and on older 1Password Linux
docs. It is **wrong for `gcr` ≥ 4 on NixOS** for two reasons:

1. `/etc/xdg/autostart/gnome-keyring-ssh.desktop` doesn't even exist in
   this stack — `gcr` 4 moved the SSH agent off the GNOME-session
   autostart pipeline entirely.
2. The `gcr-ssh-agent.socket` unit is activated by systemd directly
   (socket activation + `WantedBy=sockets.target`), so the XDG autostart
   layer never gets a vote.

Symptom after applying the (incorrect) hidden-autostart fix:

```sh
ps aux | grep gcr-ssh
# inscrip+ 1543 ... /nix/store/.../gcr-4.4.0.1/libexec/gcr-ssh-agent --base-dir /run/user/1000/gcr
ls /run/user/1000/gcr/
# srw-rw-rw- ... ssh
```

The agent was still up, and `/run/user/1000/gcr/ssh` was still
listening — we were just lucky that `$SSH_AUTH_SOCK` happened to be
exported to the 1Password path *first* in the shell environment, so
nothing actually used the gcr socket. Functional, but not what the doc
claimed.

### The actual fix

Mask the two units in the systemd user manager. The systemd lookup
order for user units puts `~/.config/systemd/user/` ahead of
`/etc/systemd/user/`, and a unit file consisting of zero bytes is
interpreted as a mask (same as a symlink to `/dev/null`, which is what
`systemctl mask` produces). So:

```nix
xdg.configFile = {
  "systemd/user/gcr-ssh-agent.socket".text = "";
  "systemd/user/gcr-ssh-agent.service".text = "";
};
```

After this is applied (`nhs`, then **re-login** so the systemd user
manager re-reads the unit catalogue):

```sh
ps aux | grep gcr-ssh                  # only grep itself
ls /run/user/$(id -u)/gcr/ssh 2>&1     # No such file or directory
systemctl --user status gcr-ssh-agent.socket
# Loaded: masked (Reason: Unit gcr-ssh-agent.socket is masked.)
```

### Why not just `services.gnome.gnome-keyring.enable = false`

The keyring daemon also implements `org.freedesktop.secrets` (the
Secret Service API), which trae-cn, vivaldi, vscode, chromium, several
git credential helpers, and other libsecret consumers depend on for
saved-password access. Disabling the whole module would silently break
all of them. We only want to defang the SSH component.

### Why not `systemd.user.services.gcr-ssh-agent.enable = false` in home-manager

home-manager's `systemd.user` module is for units **it** owns. It
refuses to overwrite or disable a unit that comes from somewhere else
(here, the NixOS system layer). Masking via a zero-byte file in
`xdg.configFile` is the documented escape hatch for exactly this
situation.

---

## 4. `~/.ssh/config`: Nix-managed in `home/core/ssh.nix`

home-manager's `programs.ssh` writes the whole `~/.ssh/config` from a
structured Nix description. We use it because:

- The two persistent host blocks on this machine (`Host *` for the
  1Password `IdentityAgent`, `Host github.com` for the
  ssh-over-port-443 fallback) are exactly the kind of low-churn,
  per-machine concern that *should* be reproducible across reinstalls.
- Storing them in nix gives the same diff/review/rollback story as the
  rest of the system: a typo in `IdentityAgent` is caught by
  `nix eval`, not by SSH failing silently with the wrong agent.
- `matchBlocks` is a real attrset, so `enableDefaultConfig = false`
  plus explicit declarations sidesteps the upcoming home-manager
  deprecation around legacy defaults.

### Current shape

```nix
# home/core/ssh.nix (excerpt)
programs.ssh = {
  enable = true;
  enableDefaultConfig = false;     # see comment in ssh.nix
  matchBlocks = {
    "*" = { identityAgent = "~/.1password/agent.sock"; };
    "github.com" = {
      hostname = "ssh.github.com";
      port = 443;
      user = "git";
    };
  };
};
```

This generates a read-only `~/.ssh/config` (symlink into the nix
store) on the next `nhs`. The `enableDefaultConfig = false` line opts
out of home-manager's legacy "set every common ssh_config knob to its
already-OpenSSH-default value" behaviour, which is on its way to
deprecation and otherwise emits an eval warning.

### Adding a host

For anything that should persist, add another entry to `matchBlocks`
and `nhs`:

```nix
"prod-jump" = {
  hostname = "jump.example.com";
  user = "ops";
  port = 2222;
  forwardAgent = true;
};
```

For a *truly temporary* one-off (a customer's box you'll touch once
this week and never again), don't bother nix-ifying it. Use:

```sh
ssh -o IdentityAgent=~/.1password/agent.sock \
    -o User=root \
    -p 2222 host.example.com
```

or, if you'll hit it several times in a session, drop a stanza into
`~/.ssh/config.d/scratch` and add `Include config.d/scratch` to the
nix config once. We are explicitly *not* doing that today because the
need hasn't materialised yet.

### How `matchBlocks` order is preserved

home-manager runs the attrset through `lib.hm.dag.topoSort` before
rendering, so attribute insertion order in the nix file determines
the order of `Host` blocks in `~/.ssh/config`. The `Host *` catch-all
is intentionally placed first in the attrset and is then re-emitted
last by home-manager (after every named block), which matches the
"most-specific-wins" matching semantics OpenSSH applies top-down.

---

## 5. First-time migration (one-shot, do once after `nhs`)

1. `nhs` so the system picks up the 1Password packages and the keyring
   autostart override.
2. Log out and back in (or reboot) so the new XDG autostart state takes
   effect and `gcr-ssh-agent` does not start.
3. Launch 1Password from the app menu, sign in, leave it running in the
   tray.
4. 1Password → Settings → Developer → "Use the SSH agent" → on. Optional
   but recommended: "Display key names when authorizing connections".
5. Import the existing key: 1Password → New Item → SSH Key → Add Private
   Key → select `~/.ssh/id_ed25519`. Save it to your personal vault.
   Importing (not generating) preserves the fingerprint, so:
    - GitHub `authorized_keys` entries keep working
    - `home/core/git.nix`'s hardcoded `signingkey = ...` stays valid
    - `configuration.nix`'s `users.users.*.openssh.authorizedKeys` stays
      valid
6. Hand off `~/.ssh/config` to home-manager. The file currently on
   disk was written by hand and is a plain file; home-manager will
   refuse to overwrite it on `nhs` ("would clobber existing file") so
   you must move it out of the way first:
   ```sh
   mv ~/.ssh/config ~/.ssh/config.pre-nix.bak
   nhs                                     # now generates the symlink
   ls -l ~/.ssh/config                     # -> /nix/store/...-ssh_config
   diff <(cat ~/.ssh/config) ~/.ssh/config.pre-nix.bak
   ```
   The `diff` should show only cosmetic changes (whitespace,
   `enableDefaultConfig=false` dropping the legacy default block).
   Once you've eyeballed it, `rm ~/.ssh/config.pre-nix.bak`.
7. Smoke test:
   ```sh
   ls -l ~/.1password/agent.sock          # srw------- inscripoem
   ssh-add -l                              # lists the ed25519 key
   ssh -T git@github.com                   # first call pops the 1Password approval dialog
   ```
8. Once smoke test passes, optionally delete the on-disk private key:
   ```sh
   shred -u ~/.ssh/id_ed25519
   # keep ~/.ssh/id_ed25519.pub; it's public anyway
   ```

---

## 6. `git commit -S` signs through 1Password directly

`home/core/git.nix` sets:

```nix
gpg.format = "ssh";
gpg.ssh.program = lib.getExe' pkgs._1password-gui "op-ssh-sign";
commit.gpgsign = true;
tag.gpgsign = true;
```

so each commit/tag goes:

```
git  ──►  op-ssh-sign (setuid-free helper from 1Password GUI pkg)
                │
                ▼
       1Password desktop app
                │
        looks up the SSH key
        whose public half matches
        `user.signingkey` in git.nix
                │
                ▼
        signature returned to git
```

Why this and not the older "let git find a key via `$SSH_AUTH_SOCK`"
path:

- **Faster.** No OpenSSH agent round-trip; `op-ssh-sign` talks the
  1Password protocol directly.
- **Independent of agent state.** Works even if `$SSH_AUTH_SOCK` is
  unset, masked, or the agent.toml excludes the signing vault for
  some reason. `op-ssh-sign` looks the key up by its public half (the
  `user.signingkey` literal), not via agent enumeration. That makes
  the historical `error: Couldn't find key in agent?` failure mode
  structurally impossible here.
- **Single source of trust.** Both auth *and* signing now resolve in
  the same vault, so granting/revoking a single 1Password item flips
  both behaviours in lockstep.

Caveats:

- **Hard-coupled to 1Password.** To fall back to a local key file you
  must comment out the `gpg.ssh.program` line and `nhs`. Recovery
  procedure in §7 covers this.
- **First-time prerequisite.** The signing key must already be in
  1Password before this is enabled, otherwise every commit fails with
  `couldn't find a key matching ...`. On `briefcase` this is true
  today; for a fresh machine, finish §5 first.

---

## 7. Recovery: what if 1Password breaks tomorrow

If the desktop app refuses to launch / sync / unlock and you need SSH
back **right now**:

1. From another device where 1Password still works: open the SSH Key
   item, "⋯" menu → Export → Private Key. Save it as
   `~/.ssh/id_ed25519`, `chmod 600`.
2. On `briefcase`, comment out (or override) the `home.sessionVariables`
   block in `home/secrets/1password.nix` so `$SSH_AUTH_SOCK` is empty.
3. Either (a) comment out the `"*"` matchBlock entry in
   `home/core/ssh.nix` and `nhs`, **or** (b) faster: bypass the
   nix-rendered config entirely with
   `ssh -F /dev/null -i ~/.ssh/id_ed25519 …` for the duration of the
   outage.
4. Run `ssh-add ~/.ssh/id_ed25519` — falls back to the systemd
   user-session ssh-agent (or just uses the on-disk file via `IdentityFile`).

This is also why we did **not** delete the local public key file in
step 5 above: fingerprint comparison during recovery uses it.

---

## 8. Common failure modes

| Symptom | Likely cause |
|---|---|
| `ls -l ~/.1password/agent.sock` says "No such file" | 1Password app not running, not signed in, or "Use the SSH agent" toggle off |
| `ssh-add -l` returns "Could not open a connection to your authentication agent" | `$SSH_AUTH_SOCK` not exported in this shell — re-login or `source ~/.zshenv` |
| `ssh-add -l` shows keys you didn't import (or a different fingerprint than 1Password) | `gcr-ssh-agent` won the race for `$SSH_AUTH_SOCK`. Run `systemctl --user status gcr-ssh-agent.socket` — if it's not "masked", the home-manager mask in `home/secrets/1password.nix` is missing or didn't apply (often: last `nhs` skipped, or you never re-logged in after the change). See §3. |
| `ps aux \| grep gcr-ssh-agent` still shows the process even with units masked | a stale instance from before the last re-login. `pkill gcr-ssh-agent` and confirm the socket file `/run/user/<uid>/gcr/ssh` does not get recreated. |
| `ssh-add -l` says "The agent has no identities" | `agent.toml` excludes the vault that holds your keys. Default app-generated content is `vault = "Employee"`; check what `home/secrets/1password.nix` is rendering (`cat ~/.config/1Password/ssh/agent.toml` should show `vault = "加密密钥"`). |
| `git commit -S` fails with `error: Couldn't find key in agent?` | usually the same root cause as the row above: the agent has no keys to enumerate. Since §6 we go through `op-ssh-sign` instead, so this error should no longer reach git; if you still see it, `gpg.ssh.program` did not get applied (`git config --get gpg.ssh.program` should print a path containing `1password-gui`). |
| 1Password browser extension says "1Password is locked" and won't unlock automatically when you unlock the desktop app | the browser is not in the GUI's allowlist. Firefox/Chrome/Brave are recognised by default; vivaldi/wavebox/other Chromium forks need to be added to `/etc/1password/custom_allowed_browsers` (handled in `system/1password.nix`). After `nhs`, restart the browser. |
| 1Password prompts on every single `git push` | expected default; turn off "Require confirmation for SSH requests" in Settings → Developer, or set a longer remember-me window |
| `Too many authentication failures` against a server | you have >6 keys exposed via `agent.toml`. Narrow the list: list specific items above the catch-all vault entry, or add `IdentityFile` per-host. |

---

## 9. 1Password Linux-app integration cheatsheet

Three knobs land on disk via Nix; everything else is in the 1Password
GUI Settings panel.

### Browser extension auto-unlock

| Browser | Auto-recognised? | What we do |
|---|---|---|
| Firefox / Chrome / Chromium / Brave | yes (hardcoded in the GUI) | nothing |
| Vivaldi | no | append `vivaldi-bin` to `/etc/1password/custom_allowed_browsers` (already done in `system/1password.nix`) |
| Anything from Flatpak/Snap | no, **cannot be fixed** | sandbox cuts the native-messaging socket; switch to a NixOS-packaged build instead |

To extend to another browser (wavebox, librewolf, ...): `ps aux | grep
<browser>`, take the binary name, add a line to the
`custom_allowed_browsers` text in `system/1password.nix`, `nhs`, restart
the browser.

### System-authentication unlock (fingerprint / login password)

Polkit policy is already wired by `programs._1password-gui.polkitPolicyOwners`
in `system/1password.nix`, and Plasma runs a polkit agent by default, so
the auth prompt has a UI to attach to. The actual "use my login
password" or "use my fingerprint" *toggle* lives in 1Password →
Settings → Security; there is no Nix knob for it.

Fingerprint unlock additionally needs `services.fprintd.enable = true`
(not enabled today on `briefcase` — no sensor).

### SSH agent allowlist (`agent.toml`)

Rendered from `home/secrets/1password.nix` into
`~/.config/1Password/ssh/agent.toml`:

```toml
[[ssh-keys]]
vault = "加密密钥"
```

To verify after `nhs`:

```sh
cat ~/.config/1Password/ssh/agent.toml      # should show the vault line
ssh-add -l                                  # should list ed25519 keys
ssh-add -L | ssh-keygen -lf -               # fingerprint must match 1Password's
```

#### First-time handover from the GUI-generated file

The 1Password app writes its own `agent.toml` when you click "Configure
for SSH agent" in the desktop GUI. That file is a regular file (not a
symlink), so home-manager will refuse to overwrite it. If you have
one — including the typical Nix-config-bootstrap case where the GUI
guessed `vault = "Employee"` — back it up first:

```sh
mv ~/.config/1Password/ssh/agent.toml ~/.config/1Password/ssh/agent.toml.gui.bak
nhs
ls -l ~/.config/1Password/ssh/agent.toml    # -> /nix/store/...-agent.toml
diff ~/.config/1Password/ssh/agent.toml.gui.bak ~/.config/1Password/ssh/agent.toml
rm  ~/.config/1Password/ssh/agent.toml.gui.bak
```

1Password picks up changes to the file live; no app restart needed.

## 10. Future-proofing: this config and other hosts (WSL, vm, headless)

This module is currently shared by every entry in `flake.nix`
(`briefcase`, `vm`) because both point at the same `./configuration.nix`
and `./home`. That works *today* by accident — `briefcase` is the only
host where 1Password is exercised in earnest. Three future scenarios
where this assumption will break, and what to do about each:

### 10.1 The `vm` host

The configuration evaluates fine on `vm` (verified: `nix eval
.#nixosConfigurations.vm.config.system.build.toplevel.drvPath`
exits 0). What runtime behaviour you get depends on what `vm` is
*for*:

- Used as a desktop clone of `briefcase` (same plasma, same account):
  works after a one-shot `1password` GUI sign-in inside the VM. Same
  vault `加密密钥` must be reachable on whatever 1P account you
  sign in with, or `agent.toml` needs an override.
- Used as a short-lived test bed for nix changes: 1P GUI starts, but
  you almost certainly never sign in to it, so `~/.1password/agent.sock`
  never appears. Anything calling `$SSH_AUTH_SOCK` (git push,
  `ssh somewhere`, `op-ssh-sign`) hangs or fails. Eval / build /
  dry-activate paths are unaffected — pure-nix tasks are fine.
- Used as a headless server (no desktop session at all): the closure
  still pulls in plasma-shaped X dependencies via `_1password-gui`
  but nothing ever uses them. ~500 MB of dead weight in the store
  per generation, no functional damage.

So `vm` is "harmless but wasteful" today. The fix-when-it-matters
plan is in §10.3.

### 10.2 A future WSL host

WSL is a fundamentally different shape: there is *no Linux 1Password
GUI*. The agent lives on the Windows host; WSL forwards SSH requests
across the wsl-interop boundary. Two officially supported paths
(see [the 1Password WSL docs](https://developer.1password.com/docs/ssh/integrations/wsl/)):

| Path | Who runs ssh | `$SSH_AUTH_SOCK` | When to pick it |
|------|--------------|------------------|-----------------|
| **`ssh.exe` alias** (1P-recommended) | Windows OpenSSH, invoked from WSL via interop | unset; just `alias ssh=ssh.exe` and `git config --global core.sshCommand ssh.exe` | pure-WSL workflows, no devcontainers |
| **socat + npiperelay bridge** | WSL's own `ssh` | `/tmp/1password-agent.sock` (a UNIX socket fronted by `socat` relaying to `\\.\pipe\openssh-ssh-agent`) | you go into docker/devcontainers from WSL, or want a single `ssh` UX |

In **neither** path is the current `home/secrets/1password.nix` reusable
as-is. Concretely the breakages are:

| Current config | Breakage on WSL |
|----------------|-----------------|
| `system/1password.nix` (GUI module) | not applicable, must be skipped |
| `SSH_AUTH_SOCK = ~/.1password/agent.sock` | wrong path; the socket lives at `/tmp/1password-agent.sock` (bridge) or doesn't exist at all (alias path) |
| `IdentityAgent ~/.1password/agent.sock` in ssh.nix | same path issue; or, alias path makes `IdentityAgent` irrelevant since `ssh.exe` reads `%USERPROFILE%/.ssh/config` instead of `~/.ssh/config` |
| `gpg.ssh.program = op-ssh-sign` (from `pkgs._1password-gui`) | the binary doesn't exist (no GUI package on WSL); signing must go through `op-ssh-sign.exe` on the Windows side, or via `core.sshCommand = ssh.exe` |
| `agent.toml` allowlist | meaningless; the only `agent.toml` that matters lives in `%LOCALAPPDATA%\1Password\config\ssh\agent.toml` on Windows |
| `gcr-ssh-agent` mask | harmless no-op (gnome-keyring isn't in WSL anyway) |

### 10.3 The migration plan (do this when a second host actually needs
*different* behaviour, not before)

Today the repo is single-host-shaped:

```
nix-config/
├── configuration.nix      # shared body
├── system/1password.nix   # shared, imported by configuration.nix
├── home/                  # shared, imported per-host in flake.nix
└── hosts/
    ├── briefcase/
    └── vm/
```

The reshape that gives clean per-host divergence:

```
nix-config/
├── hosts/
│   ├── briefcase/
│   │   ├── default.nix          # imports ../../shared + the 1P modules
│   │   └── home.nix
│   ├── vm/
│   │   ├── default.nix          # imports ../../shared, NOT the 1P modules
│   │   └── home.nix
│   └── <wsl-host>/
│       ├── default.nix          # imports ../../shared + 1password-wsl
│       └── home.nix
├── shared/
│   ├── system/                  # everything every host gets
│   └── home/
├── system/
│   ├── 1password.nix            # briefcase-only (Linux GUI flavour)
│   └── 1password-wsl.nix        # wsl-only (interop + bridge flavour)
└── home/
    └── secrets/
        ├── 1password-linux.nix  # what we have today
        └── 1password-wsl.nix    # socat bridge + ssh.exe aliases
```

`flake.nix` then picks `./hosts/<host>/default.nix` instead of the
flat `./configuration.nix`.

This is **YAGNI** today: there is no WSL host, and `vm` doesn't
*need* per-host divergence, it just *wastes some closure* without it.
The right trigger to actually do this work is *"I am sitting in front
of a WSL machine and need it set up tonight"* — not now.

What to **not** do in the meantime:

- Don't pre-emptively wrap modules in `lib.mkIf isWsl ...`. Nix
  only evaluates the branch your host hits, so the other branch is
  untestable dead code that rots silently. By the time you switch
  on WSL the assumed paths / binary names / 1P pipe name will all
  have drifted.
- Don't build a `options.mySsh.agent.backend = enum [ ... ]`
  abstraction for one real backend. Abstractions earn their cost
  only when there's actual variation to factor.

The cheapest hedge today (which we've already paid the cost of):
keep this section of the doc up to date so future-you doesn't have
to re-derive what breaks where.
