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

    go.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Go toolchain (go)";
    };

    build.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Generic build tools (just / devenv)";
    };
  };

  config = {
    home.packages =
      lib.optionals cfg.node.enable [
        pkgs.bun
        pkgs.nodejs_22
        pkgs.pnpm
        pkgs.yarn
      ]
      ++ lib.optional cfg.python.enable pkgs.uv
      ++ lib.optional cfg.rust.enable pkgs.rustup
      ++ lib.optional cfg.go.enable pkgs.go
      ++ lib.optionals cfg.build.enable [
        pkgs.just
        pkgs.devenv
      ];

    # cargo install puts binaries in ~/.cargo/bin; rustup expects it on PATH
    # ahead of the profile so its shims resolve to the active toolchain.
    # go install puts binaries in ~/go/bin.
    home.sessionPath = lib.mkMerge [
      (lib.mkIf cfg.rust.enable [
        "${config.home.homeDirectory}/.cargo/bin"
      ])
      (lib.mkIf cfg.go.enable [
        "${config.home.homeDirectory}/go/bin"
      ])
    ];
  };
}
