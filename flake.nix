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

    # nix-darwin - macOS host management (darwinConfigurations output).
    # Uses the same nixpkgs pin. Phase 1 leaves both Home Manager and the
    # existing Lix installation outside nix-darwin's ownership boundary.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
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

    # nix-index-database - weekly prebuilt nix-index databases. The home
    # module swaps programs.nix-index.package for a database-carrying
    # wrapper and adds comma (`, cmd` runs software without installing),
    # so no local `nix-index` full scan is ever needed; the database
    # refreshes with flake update. Wired in home/core/nix-index.nix.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI coding agents (claude-code, codex, opencode, antigravity-cli, rtk, ...).
    # Intentionally NOT following our nixpkgs: upstream pins its own
    # nixpkgs-unstable to guarantee binary-cache hits via cache.numtide.com.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Hermes Agent (Nous Research) upstream flake. Also pins its own nixpkgs
    # (no follows). No binary cache, but releases land here the moment
    # upstream cuts them — no waiting on llm-agents packaging.
    hermes-agent.url = "github:NousResearch/hermes-agent";

    # fcitx5-vinput - voice input addon for fcitx5 (local sherpa-onnx or
    # cloud ASR + LLM post-processing). NOT following our nixpkgs: upstream
    # pins nixos-unstable and publishes prebuilt results to
    # fcitx5-vinput.cachix.org keyed on that pin; following ours would force
    # a local sherpa-onnx rebuild on every unrelated bump.
    fcitx5-vinput.url = "github:xifan2333/fcitx5-vinput";

    # deepseek-harness - DeepSeek Harness (dsh) community packaging: CLI,
    # dsh-desktop-official Electron app (dataelement's own releases ship
    # macOS/Windows only), NixOS/HM modules. NOT following our nixpkgs:
    # upstream pins nixpkgs-unstable and publishes prebuilt results to
    # deepseek-harness-nix.cachix.org keyed on that pin.
    deepseek-harness.url = "github:moraxyc/deepseek-harness.nix";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # artcraft - storytold Craft App Suite (photocraft, vectorcraft, ...).
    # Community packaging (Devitek) of the prebuilt release tarballs; its
    # repo auto-tracks upstream releases hourly, so a flake update picks up
    # whatever is newest. Follows our nixpkgs: the packages are
    # autoPatchelf wrappers, not builds keyed to a foreign pin.
    artcraft = {
      url = "github:Devitek/artcraft-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
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

    # linuxqq-wayland-fix - LD_PRELOAD fixes for native-Wayland QQ:
    # in-app screenshot (wlr-screencopy), screen share (PipeWire +
    # portal ScreenCast) and clipboard (Wayland data-control). Tested
    # upstream on niri. Wired up in modules/nixos/desktop/qq-wayland-fix.nix.
    # Intentionally NOT following our nixpkgs: its own pin is irrelevant
    # (the module callPackages from our pkgs), and keeping it lets
    # update-versions.sh read the rev the fix currently tests against.
    # Pinned to v0.2.19 (commit); bump via scripts/update-versions.sh --only=qq.
    # NOTE: pin the commit, not the tag ref — v0.2.19 is an annotated tag,
    # and its tag object sha is invisible to raw.githubusercontent.com.
    linuxqq-wayland-fix.url = "github:SHORiN-KiWATA/linuxqq-wayland-fix/01bdc033f9b893847e7c3c4a7a8f9ce1e1143947";

    # qq pinned to the nixpkgs rev that linuxqq-wayland-fix tests against
    # (the nixpkgs rev in its own flake.lock), so the injected fixes never
    # run against an unadapted QQ build. Bump together with the fix via
    # scripts/update-versions.sh --only=qq — not by hand.
    nixpkgs-qq.url = "github:NixOS/nixpkgs/c59305bab2065cfecc4944690d9eedbb56f3a9fa";

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
