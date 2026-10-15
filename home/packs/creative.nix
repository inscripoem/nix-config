{ config, lib, pkgs, ... }:
let
  cfg = config.packs.creative;
in {
  options.packs.creative = {
    enable = lib.mkEnableOption "creative DAW / DCC toolchain";

    ardour.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "ardour — DAW";
    };

    audacity.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "audacity — audio editor";
    };

    blender.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "blender — 3D DCC";
    };

    gimp.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "gimp — raster image editor";
    };

    godot.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "godot_4 — game engine";
    };

    # Opt-in extra from the artcraft flake (defaults to false): each app is
    # a sizeable prebuilt binary closure, not pulled in with the pack.
    photocraft.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "photocraft — ArtCraft raster image editor";
    };

    zrythm.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "zrythm — DAW";
    };
  };

  config = lib.mkMerge [
    {
      home.packages =
        lib.optional cfg.ardour.enable pkgs.ardour
        ++ lib.optional cfg.audacity.enable pkgs.audacity
        ++ lib.optional cfg.blender.enable pkgs.blender
        ++ lib.optional cfg.gimp.enable pkgs.gimp
        ++ lib.optional cfg.godot.enable pkgs.godot_4
        ++ lib.optional cfg.zrythm.enable pkgs.zrythm;
    }
    # photocraft comes from the artcraft flake's HM module, not nixpkgs.
    (lib.mkIf cfg.photocraft.enable {
      programs.artcraft = {
        enable = true;
        apps = [ "photocraft" ];
      };
    })
  ];
}
