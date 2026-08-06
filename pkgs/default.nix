final: prev: {
  harmonyos-sans = final.callPackage ./harmonyos-sans.nix { };
  siyuan = final.callPackage ./siyuan.nix { };
  "trae-cn" = final.callPackage ./trae-cn.nix { };
  "cc-switch" = final.callPackage ./cc-switch.nix { };
  notion-electron = final.callPackage ./notion-electron.nix { };
  glances = final.callPackage ./glances.nix { originalGlances = prev.glances; };
  rebarstate = final.callPackage ./rebarstate.nix { };

  ww-manager = final.callPackage ./ww-manager.nix { };
}
