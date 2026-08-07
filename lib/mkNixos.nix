{ inputs, vars, nixpkgs }:
{ arch, ... }@spec:

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
