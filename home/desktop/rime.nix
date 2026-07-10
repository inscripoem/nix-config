{ config, lib, pkgs, ... }:

let
  wanxiangGramUrl = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram";
in
{
  # ── 万象拼音方案声明式配置 ──────────────────────────────

  # 1. 启用万象作为默认 rime 方案
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = ''
    patch:
      __include: wanxiang_suggested_default:/
  '';

  # 2. 首次部署时下载万象 ngram 语法模型（~200MB）
  home.activation.downloadWanxiangGram = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GRAM="$HOME/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram"
    if [ ! -f "$GRAM" ]; then
      echo "→ Downloading Wanxiang LTS grammar model (~200MB)..."
      $DRY_RUN_CMD curl -fLo "$GRAM" \
        "${wanxiangGramUrl}" \
        || echo "⚠ Skipped (offline?). Run 'update-wanxiang-gram' later."
    fi
  '';

  # 3. 手动刷新语法模型到最新版
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
