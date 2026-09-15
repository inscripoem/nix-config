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
dictionaries, and `default.yaml` from the `rime-wanxiang` input pinned in
`flake.lock`. This keeps those files at the same upstream revision while
retaining other bundled schemas.

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

After a successful download, use Deploy in the Fcitx5 tray menu.

## Applying patches

Deploy after changing schema or dictionary configuration. If changes remain
stale, close applications using the input method, move the generated cache to
an unused backup path, and Deploy again:

```sh
rime_cache_backup=$(mktemp -d "$HOME/rime-build-backup.XXXXXX")
mv ~/.local/share/fcitx5/rime/build "$rime_cache_backup/"
```

This workaround was needed during setup with managed configuration links. It
is a fallback for stale generated files, not a requirement to delete user
dictionaries on every update.

References: [Wanxiang](https://github.com/amzxyz/rime_wanxiang),
[grammar releases](https://github.com/amzxyz/RIME-LMDG/releases),
[Rime configuration](https://wiki.archlinux.org/title/Rime#Apply_configuration).
