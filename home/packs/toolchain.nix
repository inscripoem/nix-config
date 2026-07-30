{ config, lib, pkgs, ... }:
let
  cfg = config.packs.toolchain;
in {
  options.packs.toolchain = {
    enable = lib.mkEnableOption "language toolchain (node/python/rust) + build tools";

    node.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Node.js toolchain (bun / nodejs_22 / pnpm / yarn)";
    };

    python.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Python toolchain (uv)";
    };

    rust.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Rust toolchain (rustup)";
    };

    build.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Generic build tools (just / devenv)";
    };
  };

  config.home.packages =
    lib.optionals cfg.node.enable [
      pkgs.bun
      pkgs.nodejs_22
      pkgs.pnpm
      pkgs.yarn
    ]
    ++ lib.optional cfg.python.enable pkgs.uv
    ++ lib.optional cfg.rust.enable pkgs.rustup
    ++ lib.optionals cfg.build.enable [
      pkgs.just
      pkgs.devenv
    ];
}
