{ self, nixpkgs, home-manager, plasma-manager, disko, llm-agents, zen-browser, niri, colmena, deploy-rs, sops-nix, impermanence, ... }@inputs:
let
  vars = import ../vars;
  lib = import ../lib { inherit (nixpkgs) lib; };

  # Desktop-oriented HM shared modules (plasma-manager, zen-browser).
  desktopHmModules = [
    plasma-manager.homeModules.plasma-manager
    zen-browser.homeModules.beta
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
        { nixpkgs.overlays = [ niri.overlays.niri ]; }
      ];
      extraConfig = {
        modules.capabilities.gaming.enable = true;
        modules.capabilities.sunshine.enable = true;
        modules.capabilities."1password".enable = true;
        modules.capabilities.smart.enable = true;
        modules.capabilities.deploy-tools.enable = true;
        modules.capabilities.remote-builder.enable = true;
        modules.capabilities.tailscale.enable = true;
      };
    };

    vm = {
      arch = "x86_64-linux";
      hardwarePath = ../hosts/vm;
      classes = [ "vm" "desktop" "lan" ];
      hmEntryPoint = ../home/hosts/vm.nix;
      hmSharedModules = desktopHmModules;
      deploy = false;
      extraModules = [ ];
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
  };

  mkNixos = import ../lib/mkNixos.nix {
    inherit inputs vars nixpkgs home-manager sops-nix;
  };

  nixosConfigurations = nixpkgs.lib.mapAttrs (name: spec:
    mkNixos (spec // { inherit name; })
  ) nixosHosts;
in
{
  inherit nixosHosts nixosConfigurations;
  colmena = import ./colmena.nix (inputs // { inherit nixosHosts vars; });
  deploy = import ./deploy.nix (inputs // { inherit nixosHosts; });

  # Colmena 0.5 requires this output for direct flake evaluation.
  colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
}
