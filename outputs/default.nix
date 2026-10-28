{ self, nixpkgs, plasma-manager, disko, zen-browser, artcraft, niri, ... }@inputs:
let
  vars = import ../vars;

  # Desktop-oriented HM shared modules (plasma-manager, zen-browser,
  # artcraft apps).
  desktopHmModules = [
    plasma-manager.homeModules.plasma-manager
    zen-browser.homeModules.beta
    artcraft.homeManagerModules.default
  ];

  # niri-flake still requires libdisplay-info 0.2, which was removed from
  # nixpkgs unstable on 2026-08-04. Reuse the exact 0.2.0 package from
  # niri-flake's own stable nixpkgs input until upstream supports 0.3.
  niriCompatOverlay = _final: prev: {
    libdisplay-info_0_2 =
      niri.inputs.nixpkgs-stable.legacyPackages.${prev.stdenv.hostPlatform.system}.libdisplay-info_0_2;
  };
  niriOverlays = [
    niriCompatOverlay
    niri.overlays.niri
  ];

  # Host declaration table — class/capability model.
  nixosHosts = {
    briefcase = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/briefcase;
      classes = [ "desktop" "lan" ];
      hmEntryPoint = ../home/hosts/briefcase.nix;
      hmSharedModules = desktopHmModules;
      deploy = false;
      extraModules = [
        disko.nixosModules.disko
        niri.nixosModules.niri
        { nixpkgs.overlays = niriOverlays; }
      ];
      extraConfig = {
        modules.capabilities.gaming = {
          enable = true;
          # AAGL launchers must be enabled explicitly (they each pull a
          # large wine closure). Currently: Genshin + HSR only.
          aagl.anime-game-launcher.enable = true;
          aagl.honkers-railway-launcher.enable = true;
          # aagl.sleepy-launcher.enable = true;  # Zenless Zone Zero
        };
        modules.capabilities.sunshine = {
          enable = true;
          # Reserved fake streaming output port (capabilities/sunshine.nix):
          # host-specific — this GPU enumerates HDMI-A-1 free of monitors.
          # Must be an HDMI port: a forced DP connector has no DPCD (no
          # physical sink), so i915 validates modes against the fallback
          # link and only 640x480 survives; HDMI mode validation works
          # from the injected EDID alone.
          fakeOutputName = "HDMI-A-1";
        };
        modules.capabilities."1password".enable = true;
        modules.capabilities.smart.enable = true;
        modules.capabilities.deploy-tools.enable = true;
        modules.capabilities.remote-builder.enable = true;
        modules.capabilities.tailscale.enable = true;
        modules.capabilities.wifi-profiles.enable = true;
        modules.capabilities.docker.enable = true;
        modules.capabilities.lan-mouse.enable = true;
        modules.capabilities.bluetooth.enable = true;
        # NCT6798 fan duty + ENE 6K7750 ARGB (Maxsun B760M D4 hardware).
        modules.capabilities.fan-argb.enable = true;
      };
    };

    vm = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/vm;
      classes = [ "vm" "desktop" "lan" ];
      hmEntryPoint = ../home/hosts/vm.nix;
      hmSharedModules = desktopHmModules;
      deploy = false;
      extraModules = [
        niri.nixosModules.niri
        { nixpkgs.overlays = niriOverlays; }
      ];
      extraConfig = {
        modules.capabilities.tailscale.enable = true;
      };
    };

    wyse3040 = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/wyse3040;
      classes = [ "server" "lan" ];
      hmEntryPoint = ../home/hosts/wyse3040.nix;
      hmSharedModules = [ ];
      deploy = true;
      hostname = "wyse3040.local";
      sshUser = "root";
      tags = [ "home" ];
      extraModules = [ disko.nixosModules.disko ];
      extraConfig = {
        modules.capabilities.tailscale.enable = true;
        modules.capabilities.sdcard.enable = true;
        modules.capabilities.impermanence.enable = true;
        modules.capabilities.remote-build-client.enable = true;
        modules.capabilities.docker.enable = true;
      };
    };

    nutshell = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/nutshell;
      classes = [ "wsl" ];
      hmEntryPoint = ../home/hosts/nutshell.nix;
      hmSharedModules = [ ];
      deploy = false;
      extraModules = [ ];
      extraConfig = { };
    };
  };

  mkNixos = import ../lib/mkNixos.nix {
    inherit inputs vars nixpkgs;
  };

  nixosConfigurations = nixpkgs.lib.mapAttrs (name: spec:
    mkNixos (spec // { inherit name; })
  ) nixosHosts;

  # macOS hosts use only fields consumed by the Darwin assembler. Deployment
  # stays local (darwin-rebuild); colmena/deploy-rs are NixOS-only.
  mkDarwin = import ../lib/mkDarwin.nix {
    inherit inputs vars;
  };

  darwinHosts = {
    air = {
      arch = "aarch64-darwin";
      hostModule = ../hosts/air;
      hmEntryPoint = ../home/hosts/air.nix;
    };
  };

  darwinConfigurations = nixpkgs.lib.mapAttrs (name: spec:
    mkDarwin (spec // { inherit name; })
  ) darwinHosts;
in
{
  inherit nixosHosts nixosConfigurations darwinHosts darwinConfigurations;
  colmena = import ./colmena.nix (inputs // { inherit nixosHosts vars; });
  deploy = import ./deploy.nix (inputs // { inherit nixosHosts; });

  # Colmena 0.5 requires this output for direct flake evaluation.
  colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
}
