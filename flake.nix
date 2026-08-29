{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI coding agents (claude-code, codex, opencode, antigravity-cli, rtk, ...).
    # Intentionally NOT following our nixpkgs: upstream pins its own
    # nixpkgs-unstable to guarantee binary-cache hits via cache.numtide.com.
    llm-agents.url = "github:numtide/llm-agents.nix";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # niri - scrollable-tiling Wayland compositor
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # colmena - remote deployment tool for NixOS
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # deploy-rs - simple rsync-based NixOS deployment
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix - declarative secret management via SOPS (age-encrypted
    # files decrypted at activation to /run/secrets). Used for WiFi PSKs
    # and other host secrets that must not enter the Nix store or git
    # history. See docs/secrets.md.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # rime-wanxiang: track upstream directly for latest schemas/dicts.
    # flake = false means we treat this as a plain source tree (not a flake).
    rime-wanxiang = {
      url = "github:amzxyz/rime_wanxiang/wanxiang";
      flake = false;
    };

    impermanence.url = "github:nix-community/impermanence";

    # nix-flatpak - declarative Flatpak package management
    nix-flatpak.url = "github:gmodena/nix-flatpak/v0.7.0";

    # anime game launchers (原神/星铁/绝区零)
    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      # aagl still pins a rust-overlay that uses the deprecated stdenv.is*
      # aliases (nixpkgs deprecation 2026-05-09); force our newer pin so
      # evaluation stays warning-free.
      inputs.rust-overlay.follows = "rust-overlay";
    };

    # rust toolchain overlay; also injected into aagl (see above).
    rust-overlay.url = "github:oxalica/rust-overlay";

    # nixos-wsl - run NixOS as a WSL2 distribution. The `wsl` class
    # imports its default module; the `wsl` host additionally exposes
    # `config.system.build.tarballBuilder` for producing a `.wsl` image
    # importable via `wsl --install --from-file`.
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: import ./outputs inputs;
}