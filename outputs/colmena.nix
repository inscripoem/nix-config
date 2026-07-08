{ self, nixpkgs, nixosHosts, ... }@inputs:
let
  # Only hosts with deploy = true become colmena nodes.
  deployableHosts = nixpkgs.lib.filterAttrs (_: spec: spec.deploy or false) nixosHosts;
in
{
  meta = {
    # colmena requires at least one nixpkgs instance in meta
    nixpkgs = import nixpkgs { system = "x86_64-linux"; };
  };
} // nixpkgs.lib.mapAttrs (name: spec: {
  # Reference the already-built nixosConfiguration as a module.
  # The NixOS module system accepts a full configuration attrset as an import.
  imports = [ self.nixosConfigurations.${name} ];
  deployment = {
    targetHost = spec.hostname or name;
    targetUser = spec.sshUser or "root";
    tags = spec.tags or [ ];
  };
}) deployableHosts