{ self, nixpkgs, deploy-rs, nixosHosts, ... }:
let
  # Only hosts with deploy = true become deploy-rs nodes.
  deployableHosts = nixpkgs.lib.filterAttrs (_: spec: spec.deploy or false) nixosHosts;
in
{
  nodes = nixpkgs.lib.mapAttrs (name: spec:
    let
      arch = spec.arch or "x86_64-linux";
    in
    {
      hostname = spec.hostname or name;
      sshUser = spec.sshUser or "root";
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${arch}.activate.nixos self.nixosConfigurations.${name};
      };
    }
  ) deployableHosts;
}