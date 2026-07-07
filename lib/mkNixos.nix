{ inputs, vars, nixpkgs, home-manager }:
{ name, arch, hardwarePath, extraModules ? [ ], hmSharedModules ? [ ] }:

let
  # Generic home-manager wiring block — only universal settings.
  # Desktop/server-specific sharedModules are passed in per-host via hmSharedModules.
  homeManagerBlock = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = hmSharedModules;
      backupFileExtension = "backup";

      users.${vars.username} = import ../home;

      extraSpecialArgs = inputs;
    };
  };
in
nixpkgs.lib.nixosSystem {
  system = arch;
  modules = extraModules ++ [
    hardwarePath
    ../configuration.nix
    home-manager.nixosModules.home-manager
    {
      nixpkgs.overlays = [ (import ../pkgs) ];
    }
    homeManagerBlock
  ];
}