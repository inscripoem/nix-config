{ self, nixpkgs, home-manager, plasma-manager, disko, llm-agents, zen-browser, niri, colmena, deploy-rs, sops-nix, impermanence, ... }@inputs:
let
  vars = import ../vars;
  lib = import ../lib { inherit (nixpkgs) lib; };

  # Desktop-oriented HM shared modules (plasma-manager, zen-browser).
  # Servers/WSL would use a different (or empty) list.
  desktopHmModules = [
    plasma-manager.homeModules.plasma-manager
    zen-browser.homeModules.beta
  ];

  # Host declaration table
  nixosHosts = {
    briefcase = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/briefcase;
      hmEntryPoint = ../home/hosts/briefcase.nix;
      deploy = false;
      extraModules = [
        ../modules/nixos/desktop
        disko.nixosModules.disko
        niri.nixosModules.niri
        { nixpkgs.overlays = [ niri.overlays.niri ]; }
        ../modules/nixos/1password.nix
        ../modules/nixos/gaming.nix
      ];
      hmSharedModules = desktopHmModules;
    };
    vm = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/vm;
      hmEntryPoint = ../home/hosts/vm.nix;
      deploy = false;
      extraModules = [
        ../modules/nixos/desktop
        ../modules/nixos/1password.nix
        ../modules/nixos/gaming.nix
      ];
      hmSharedModules = desktopHmModules;
    };
    wyse3040 = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/wyse3040;
      hmEntryPoint = ../home/hosts/wyse3040.nix;
      deploy = true;
      hostname = "wyse3040.local";
      sshUser = "root";
      tags = [ "home" ];
      extraModules = [ disko.nixosModules.disko ];
      hmSharedModules = [ ];
    };
  };

  mkNixos = import ../lib/mkNixos.nix {
    inherit inputs vars nixpkgs home-manager sops-nix;
  };

  nixosConfigurations = nixpkgs.lib.mapAttrs (name: spec:
    mkNixos {
      inherit name;
      inherit (spec) arch hardwarePath extraModules hmSharedModules hmEntryPoint;
    }
  ) nixosHosts;
in
{
  inherit nixosHosts nixosConfigurations;
  colmena = import ./colmena.nix (inputs // { inherit nixosHosts vars; });
  deploy = import ./deploy.nix (inputs // { inherit nixosHosts; });

  # Colmena 0.5 requires this output for direct flake evaluation.
  # makeHive evaluates the raw hive config and returns the v0.5 schema.
  colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
}