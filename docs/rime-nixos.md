# Rime on NixOS

Fcitx5 uses the Wanxiang schema. The system's
[input-method module](../modules/nixos/desktop/input-method.nix) supplies Rime
data; [home/desktop/rime.nix](../home/desktop/rime.nix) manages user patches,
dictionary links, and the grammar-model download.

Wanxiang was chosen to improve candidate ordering and long-form contextual
suggestions over the previous stock Rime setup. Its dictionaries and LTS ngram
grammar model addressed that need while fitting the existing Fcitx5 stack.
The model download remains a separate maintenance step, described below.

## Configuration

The system module replaces the bundled Wanxiang files with schemas, Lua,
dictionaries, `default.yaml`, `custom_phrase.dict.yaml`, and the `opencc/`
directory from the `rime-wanxiang` input pinned in `flake.lock`. The opencc
txt dictionaries are compiled into `.ocd2` binaries during the package build
(adding `opencc` to `nativeBuildInputs`), replicating what upstream CI does
before packaging; the emoji and s2t/s2hk/s2tw opencc configs only reference
the `.ocd2` files. Missing `custom_phrase.dict.yaml` or the compiled opencc
data makes Deploy fail while typing keeps working. This keeps those files at
the same upstream revision while retaining other bundled schemas.

HM's `default.custom.yaml` explicitly selects the `wanxiang` schema. The system
supplies the default configuration directly; avoid adding a competing copy of
`default.yaml`.

The HM module links the zhwiki and moegirl dictionaries and uses comma/period
for candidate page navigation. User dictionaries under
`~/.local/share/fcitx5/rime/` are runtime data and should be backed up separately.

## Grammar model

The `.gram` model comes from an upstream LTS release whose contents can change
at the same URL. It is downloaded into the user directory rather than pinned
as a Nix build input. This means that part of the setup is not reproducible
from `flake.lock` alone.

Activation downloads the model when the file is absent. A failed download only
prints a warning; an existing or partial file is not refreshed automatically.
To download again or update it:

```sh
update-wanxiang-gram
```

After a successful download, restart fcitx5 to reload the model.

## Stale build cache

Rime's deployer recompiles a schema only when a source file's mtime is newer
than the timestamp recorded in the build cache (`~/.local/share/fcitx5/rime/build/`).
Every file inside the nix store has mtime 0, so after a flake update brings new
`rime-wanxiang` sources, Deploy never considers them newer and silently keeps
the old compiled schema. Dictionaries are checksum-based and do get rebuilt,
but the compiled `*.schema.yaml` (engine and Lua component wiring) goes stale;
running the new Lua scripts against old wiring fails per keystroke and drops
every candidate, leaving only the preedit underline with an empty candidate
window.

`home/desktop/rime.nix` guards against this: an activation script stamps the
pinned `rime-wanxiang` store path plus a hash of the managed `*.custom.yaml`
patches into `.wanxiang-src-stamp`, and when the stamp no longer matches, moves
the build cache into a backup directory so the next Deploy recompiles from
scratch. Restart fcitx5 after a switch that triggered this.

The manual fallback still works for anything the guard does not cover:

```sh
rime_cache_backup=$(mktemp -d "$HOME/rime-build-backup.XXXXXX")
mv ~/.local/share/fcitx5/rime/build "$rime_cache_backup/"
```

It is a fallback for stale generated files, not a requirement to delete user
dictionaries on every update.

## Tray deploy caveat

The fcitx5 tray Deploy action tears librime down and rebuilds it inside the
running process. With Lua-heavy schemas like Wanxiang this can leave the
engine wedged — no input response and an empty schema menu — until fcitx5 is
restarted. Apply configuration changes through a switch plus an fcitx5
restart instead; the startup maintenance performs the same recompilation
safely before any session exists.

References: [Wanxiang](https://github.com/amzxyz/rime_wanxiang),
[grammar releases](https://github.com/amzxyz/RIME-LMDG/releases),
[Rime configuration](https://wiki.archlinux.org/title/Rime#Apply_configuration).
