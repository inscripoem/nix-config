final: prev: {
  siyuan = final.callPackage ./siyuan.nix { };
  "trae-cn" = final.callPackage ./trae-cn.nix { };
  "cc-switch" = final.callPackage ./cc-switch.nix { };
  glances = final.callPackage ./glances.nix { originalGlances = prev.glances; };
  rebarstate = final.callPackage ./rebarstate.nix { };

  flatpak = final.callPackage ./flatpak.nix {
    flatpak = prev.flatpak;
  };

  bottles-unwrapped = import ./bottles.nix {
    inherit (prev) bottles-unwrapped python3Packages;
  };
}
