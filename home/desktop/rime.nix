{ config, lib, pkgs, ... }:

let
  wanxiangGramUrl = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram";
in
{
  # ── Wanxiang Pinyin declarative config ──────────────────

  # 1. Enable wanxiang as the default rime schema
  xdg.dataFile = {
    "fcitx5/rime/default.custom.yaml".text = ''
      patch:
        schema_list:
          - schema: wanxiang
    '';
    "fcitx5/rime/zhwiki.dict.yaml".source =
      "${pkgs.rime-zhwiki}/share/rime-data/zhwiki.dict.yaml";
    "fcitx5/rime/moegirl.dict.yaml".source =
      "${pkgs.rime-moegirl}/share/rime-data/moegirl.dict.yaml";
    # Use comma/period for page up/down (wanxiang defaults to minus/equal)
    "fcitx5/rime/wanxiang.custom.yaml".text = ''
      patch:
        key_binder/bindings/+:
          - {when: has_menu, accept: comma, send: Page_Up}
          - {when: has_menu, accept: period, send: Page_Down}
    '';
  };

  # 2. Download the ngram grammar model on first deploy (~200MB)
  home.activation.downloadWanxiangGram = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GRAM="$HOME/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram"
    if [ ! -f "$GRAM" ]; then
      echo "→ Downloading Wanxiang LTS grammar model (~200MB)..."
      $DRY_RUN_CMD curl -fLo "$GRAM" \
        "${wanxiangGramUrl}" \
        || echo "⚠ Skipped (offline?). Run 'update-wanxiang-gram' later."
    fi
  '';

  # 3. Command to refresh the grammar model
  home.packages = [
    (pkgs.writeShellScriptBin "update-wanxiang-gram" ''
      set -e
      GRAM="$HOME/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram"
      echo "Downloading latest Wanxiang LTS grammar model..."
      curl -fLo "$GRAM" \
        "${wanxiangGramUrl}"
      echo "Done. Open fcitx5 tray menu → Deploy to reload the model."
    '')
  ];
}
