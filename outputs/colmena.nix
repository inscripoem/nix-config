{ nixpkgs, nixosHosts, vars, ... }@flakeInputs:
let
  inherit (nixpkgs) lib;

  nixosModules = import ../lib/nixosModules.nix {
    inherit vars;
    inputs = flakeInputs;
  };

  # Only hosts with deploy = true become colmena nodes.
  deployableHosts = lib.filterAttrs (_: spec: spec.deploy or false) nixosHosts;
in
{
  meta = {
    nixpkgs = import nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit vars; inputs = flakeInputs; };
  };
} // lib.mapAttrs (name: spec: {
  imports = (nixosModules spec) ++ [
    {
      networking.hostName = name;
      deployment = {
        targetHost = spec.hostname or name;
        targetUser = spec.sshUser or "root";
        tags = spec.tags or [ ];
      };
    }
  ];
}) deployableHosts
