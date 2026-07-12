{ self, nixpkgs, nixosHosts, home-manager, sops-nix, vars, colmena, ... }@flakeInputs:
let
  lib = nixpkgs.lib;
  
  # Only hosts with deploy = true become colmena nodes.
  deployableHosts = lib.filterAttrs (_: spec: spec.deploy or false) nixosHosts;

  # Build a home-manager wiring block for a given spec.
  mkHomeManagerBlock = spec: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = spec.hmSharedModules or [ ];
      backupFileExtension = "backup";
      users.${vars.username} = import spec.hmEntryPoint;
      extraSpecialArgs = flakeInputs;
    };
  };

  # Convert a host spec into a list of NixOS modules for colmena.
  specToModules = name: spec:
    (spec.extraModules or [ ]) ++ [
      spec.hardwarePath
      ../modules/nixos/base
      ../modules/nixos/tailscale.nix
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
      { nixpkgs.overlays = [ (import ../pkgs) ]; }
      (mkHomeManagerBlock spec)
      {
        networking.hostName = name;
        deployment = {
          targetHost = spec.hostname or name;
          targetUser = spec.sshUser or "root";
          tags = spec.tags or [ ];
        };
      }
    ];
in
{
  meta = {
    nixpkgs = import nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit vars; inputs = flakeInputs; };
  };
} // lib.mapAttrs (name: spec: {
  imports = specToModules name spec;
}) deployableHosts
