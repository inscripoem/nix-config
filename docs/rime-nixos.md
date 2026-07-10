# Declarative Rime Input Method Management on NixOS

> 2026-07 · Rationale + Implementation + Operations Guide

## Why Wanxiang (rime-wanxiang)

### Weixin IME / Sogou IME ruled out

- **Weixin Input Method** (Tencent's standalone IME): as of 2026-07, Windows 2.1.0 and macOS 2.2.0 only. **No Linux release exists.** What you may have seen online about "WeChat IME on Linux" is the WeChat messaging client v4.0, not the IME.
- **Sogou Pinyin for Linux**: still ships monthly releases (16.6 in 2026-06), but the engine is **fcitx4**, not fcitx5. Under Wayland (KDE Plasma 6 / niri / Hyprland) the candidate window flickers, input breaks, and fcitx5 must be uninstalled due to conflicts. **Unusable on modern desktops.**

### Why rime-wanxiang over bare rime

Stock rime (luna_pinyin) has two pain points:
1. **Outdated word ordering**: static dictionary weights. Single-character abbreviations (e.g. typing `l` always puts 里 first, never 了) cannot be altered through user frequency learning.
2. **Stiff long-form prediction**: no ngram language model; poor contextual suggestions.

Comparison of modern rime schemas:

| Schema | Dictionary | Ngram model | Single-char pinning | Community |
|--------|-----------|-------------|---------------------|-----------|
| **rime-ice** | Hand-curated + Tencent word vectors | Optional (manual LTS mount) | Built-in `pin_cand_filter.lua` | 18k★ |
| **rime-wanxiang** | AI-optimized corpus + tone annotation | **Built-in LTS** (zero-config) | Manual config required | Active |
| rime-frost | Benchmark-optimized | Multiple models supported | Manual config required | Active |

**Decision**: rime-wanxiang ships its own LTS ngram grammar model. The core complaint about bare rime—"doesn't feel modern"—comes from the lack of a language model. Wanxiang fixes this out of the box, and is already packaged in nixpkgs.

## Declarative management

NixOS / home-manager provides ~95% declarative coverage for rime configuration:

### rimeDataPkgs injection (system-level)

```nix
i18n.inputMethod.fcitx5.addons = with pkgs; [
  (fcitx5-rime.override {
    rimeDataPkgs = [
      rime-wanxiang
      rime-zhwiki
      rime-moegirl
    ];
  })
  # ...
];
```

`rimeDataPkgs` merges each package into fcitx5-rime's `share/rime-data/` at build time. The user directory (`~/.local/share/fcitx5/rime/`) overrides / extends the system-level data.

### Schema selection + custom patch (user-level, home-manager)

```nix
xdg.dataFile."fcitx5/rime/default.custom.yaml".text = ''
  patch:
    __include: wanxiang_suggested_default:/
    schema_list:
      - schema: wanxiang
'';
```

**Why `__include` + `schema_list` override?**

Wanxiang upstream renamed `default.yaml` to `wanxiang_suggested_default.yaml` to avoid collisions with other packages' `default.yaml`. The `__include` brings in wanxiang's global settings (menu, switcher, key_binder, ascii_composer, etc.). The explicit `schema_list` override on top ensures wanxiang is activated.

**Critical pitfall**: do NOT include both `rime-data` and `rime-wanxiang` in `rimeDataPkgs`. `rime-data` provides its own `default.yaml` (with luna_pinyin, bopomofo schemas), and its `schema_list` takes priority over the patch's `__include`-merged version. This is a known collision in rime's patch merge semantics for arrays. The fix: use **only** `rime-wanxiang` + dictionary packages (`rime-zhwiki`, `rime-moegirl`), leaving `rime-data` out. When `rime-data` is absent, `fcitx5-rime` creates an empty `default.yaml` as the base, and wanxiang's `__include` + `schema_list` override applies cleanly.

### Non-declarative leftovers (~5%)

| Item | Why | Mitigation |
|------|-----|------------|
| Wanxiang `.gram` model | Upstream uses an overwriting LTS release tag; same URL points to different content over time, breaking Nix's hash immutability. nixpkgs intentionally does not package it. | `home.activation` auto-download on first deploy + manual `update-wanxiang-gram` |
| User dictionary (`.userdb`) | Generated at runtime by rime; cannot and should not be declarative. | Auto-created, do not manage manually. |
| Post-deploy schema reload | Rime must be notified after schema/dict changes. | Right-click fcitx5 tray → Deploy, or `rime_deployer --deploy` |

### Key bindings and the build cache

Wanxiang defaults to `-` / `=` for page-up / page-down. `rime.nix` overrides this to `,` / `.` via `wanxiang.custom.yaml`.

**Important**: when you add or modify any `*.custom.yaml` file, rime does not automatically recompile — even a manual Deploy may skip it if the `build/` directory already has compiled binary data that predates the change. This is rime's own deployment behavior (not specific to any package version). Clear the cache first:

```bash
rm -rf ~/.local/share/fcitx5/rime/build/
# fcitx5 tray → Deploy
```

This was hit repeatedly during setup: `schema_list` overrides, `__include` patches, and key-binding patches all required a `build/` wipe before they took effect. The root cause is that rime's deployment logic prefers pre-compiled binary data in `build/` over re-processing source `.yaml` files.

## Wanxiang ngram grammar model (`.gram`)

### First deploy

The repo configures `home.activation` to auto-download the model: **no manual steps are needed on a new machine**. `home-manager switch` (or `nixos-rebuild switch`) curls `wanxiang-lts-zh-hans.gram` into `~/.local/share/fcitx5/rime/`. If the network is unavailable, a warning is printed to stderr and the download is skipped; run `update-wanxiang-gram` later to catch up.

### Update to latest

```bash
update-wanxiang-gram
```

Fetches the latest `.gram` from the GitHub LTS release.

### Release cadence

The author publishes updates irregularly (1–3 times per year), whenever server-side training runs (GPU rental) complete. Each release overwrites the same `LTS` tag, meaning the URL always points to the current latest, without versioned releases.

Ref: https://github.com/amzxyz/RIME-LMDG/releases

## Rime build cache behavior

When rime deploys, it compiles source `.yaml` files into binary format under `~/.local/share/fcitx5/rime/build/`. After that, subsequent Deploy calls use the cached binaries — they do **not** re-parse `.custom.yaml` patches unless the build directory is cleared:

```bash
rm -rf ~/.local/share/fcitx5/rime/build/
# fcitx5 tray → Deploy
```

This is rime's own deployment logic. While the official guide says clicking ⟲ (Deploy) should suffice, in practice — especially with Nix-managed symlinked configurations — the `build/` cache often goes stale and Deploy alone does not recompile. The `rm build/` + Deploy workaround is documented on the [Arch Wiki](https://wiki.archlinux.org/title/Rime#Apply_configuration) and [Stack Overflow](https://stackoverflow.com/questions/77575270) as a reliable fallback when Deploy doesn't pick up `.custom.yaml` changes.

## References

- [rime-wanxiang](https://github.com/amzxyz/rime_wanxiang)
- [RIME-LMDG (grammar model releases)](https://github.com/amzxyz/RIME-LMDG)
- [rime-ice](https://github.com/iDvel/rime-ice) (alternative schema)
- [felixonmars/fcitx5-pinyin-zhwiki](https://github.com/felixonmars/fcitx5-pinyin-zhwiki) (zhwiki dictionary, dual-format: fcitx5 + rime)
- [outloudvi/mw2fcitx](https://github.com/outloudvi/mw2fcitx) (moegirl dictionary generator)
- [librime #377 — candidate ranking algorithm](https://github.com/rime/librime/issues/377) (dev explanation of "memory & forgetting" model)
- [Nixpkgs PR #224042 — rimeDataPkgs mechanism](https://github.com/NixOS/nixpkgs/pull/224042)
- [NixOS Wiki: Fcitx5](https://wiki.nixos.org/wiki/Fcitx5)
- [Fcitx5 Wiki: Using Fcitx 5 on Wayland](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)
