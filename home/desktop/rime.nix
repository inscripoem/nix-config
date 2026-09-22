{ lib, pkgs, rime-wanxiang, ... }:

let
  wanxiangGramUrl = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram";

  defaultCustomYaml = ''
    patch:
      schema_list:
        - schema: wanxiang
  '';

  wanxiangCustomYaml = ''
    patch:
      key_binder/bindings/+:
        - {when: has_menu, accept: comma, send: Page_Up}
        - {when: has_menu, accept: period, send: Page_Down}
  '';

  # Rime's deployer recompiles a schema only when a source file's mtime is
  # newer than the timestamp recorded in the build cache. Files from the nix
  # store always have mtime 0, so a flake update never invalidates the cache
  # and stale engine wiring runs against the new Lua scripts (empty candidate
  # list). Stamp the pinned source path plus our patches; on change, move the
  # build cache aside so the next deploy recompiles. See docs/rime-nixos.md.
  wanxiangStamp = builtins.hashString "sha256"
    (toString rime-wanxiang + defaultCustomYaml + wanxiangCustomYaml);
in
{
  # ── Wanxiang Pinyin declarative config ──────────────────

  # 1. Enable wanxiang as the default rime schema
  xdg.dataFile = {
    "fcitx5/rime/default.custom.yaml".text = defaultCustomYaml;
    "fcitx5/rime/zhwiki.dict.yaml".source =
      "${pkgs.rime-zhwiki}/share/rime-data/zhwiki.dict.yaml";
    "fcitx5/rime/moegirl.dict.yaml".source =
      "${pkgs.rime-moegirl}/share/rime-data/moegirl.dict.yaml";
    # Use comma/period for page up/down (wanxiang defaults to minus/equal)
    "fcitx5/rime/wanxiang.custom.yaml".text = wanxiangCustomYaml;
  };

  # 2. Invalidate the rime build cache when wanxiang sources change
  home.activation.refreshWanxiangBuild = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    RIME_DIR="$HOME/.local/share/fcitx5/rime"
    STAMP="$RIME_DIR/.wanxiang-src-stamp"
    if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "${wanxiangStamp}" ]; then
      if [ -d "$RIME_DIR/build" ]; then
        backup=$(mktemp -d "$HOME/rime-build-backup.XXXXXX")
        $DRY_RUN_CMD mv "$RIME_DIR/build" "$backup/"
        echo "→ Moved stale rime build cache to $backup (wanxiang sources or patches changed)"
      fi
      if [ -z "''${DRY_RUN:-}" ]; then
        printf '%s\n' "${wanxiangStamp}" > "$STAMP"
      fi
    fi
  '';

  # 3. Download the ngram grammar model on first deploy (~200MB)
  home.activation.downloadWanxiangGram = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GRAM="$HOME/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram"
    if [ ! -f "$GRAM" ]; then
      echo "→ Downloading Wanxiang LTS grammar model (~200MB)..."
      $DRY_RUN_CMD curl -fLo "$GRAM" \
        "${wanxiangGramUrl}" \
        || echo "⚠ Skipped (offline?). Run 'update-wanxiang-gram' later."
    fi
  '';

  # 4. Command to refresh the grammar model
  home.packages = [
    (pkgs.writeShellScriptBin "update-wanxiang-gram" ''
      set -e
      GRAM="$HOME/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram"
      echo "Downloading latest Wanxiang LTS grammar model..."
      curl -fLo "$GRAM" \
        "${wanxiangGramUrl}"
      echo "Done. Restart fcitx5 (or re-login) to reload the model."
    '')
  ];
}
