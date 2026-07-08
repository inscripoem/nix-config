{ self, nixpkgs, home-manager, plasma-manager, disko, llm-agents, zen-browser, niri, colmena, deploy-rs, ... }@inputs:
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
        disko.nixosModules.disko
        niri.nixosModules.niri
        { nixpkgs.overlays = [ niri.overlays.niri ]; }
      ];
      hmSharedModules = desktopHmModules;
    };
    vm = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/vm;
      hmEntryPoint = ../home/hosts/vm.nix;
      deploy = false;
      extraModules = [ ];
      hmSharedModules = desktopHmModules;
    };
  };

  mkNixos = import ../lib/mkNixos.nix {
    inherit inputs vars nixpkgs home-manager;
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
  colmena = import ./colmena.nix (inputs // { inherit nixosHosts; });
  deploy = import ./deploy.nix (inputs // { inherit nixosHosts; });
}