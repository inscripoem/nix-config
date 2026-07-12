{ inputs, vars, nixpkgs, home-manager, sops-nix }:
{ name, arch, hardwarePath, extraModules ? [ ], hmSharedModules ? [ ], hmEntryPoint ? ../home/desktop.nix }:

let
  # Generic home-manager wiring block — only universal settings.
  # Desktop/server-specific sharedModules are passed in per-host via hmSharedModules.
  homeManagerBlock = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = hmSharedModules;
      backupFileExtension = "backup";

      users.${vars.username} = import hmEntryPoint;

      extraSpecialArgs = inputs;
    };
  };
in
nixpkgs.lib.nixosSystem {
  system = arch;
  specialArgs = {
    inherit vars inputs;
  };
  modules = extraModules ++ [
    hardwarePath
    ../modules/nixos/base
    ../modules/nixos/tailscale.nix
    sops-nix.nixosModules.sops
    home-manager.nixosModules.home-manager
    {
      nixpkgs.overlays = [ (import ../pkgs) ];
    }
    homeManagerBlock
  ];
}