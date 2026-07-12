{ inputs, vars, nixpkgs, home-manager, sops-nix }:
{ name, arch, ... }@spec:

let
  nixosModules = import ./nixosModules.nix { inherit vars inputs; };
in
nixpkgs.lib.nixosSystem {
  system = arch;
  specialArgs = {
    inherit vars inputs;
  };
  modules = nixosModules spec;
}
