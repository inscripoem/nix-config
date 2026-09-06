{ inputs, vars }:
{ arch, ... }@spec:

let
  darwinModules = import ./darwinModules.nix;
in
inputs.nix-darwin.lib.darwinSystem {
  system = arch;
  specialArgs = {
    inherit vars inputs;
  };
  modules = darwinModules spec;
}
