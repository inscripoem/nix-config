{ inputs, vars }:
spec:
[
  spec.hostModule
  ../modules/darwin/base
  inputs.home-manager.darwinModules.home-manager
  # Shared package overlay (pkgs/); NixOS hosts get it via
  # lib/nixosModules.nix. Entries are lazy, so unreferenced packages
  # (e.g. the linux-only wechat wrapper) never evaluate on darwin.
  { nixpkgs.overlays = [ (import ../pkgs) ]; }
  {
    users.users.${vars.username}.home = "/Users/${vars.username}";

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "backup";
      users.${vars.username} = import spec.hmEntryPoint;
      # Expose vars to HM modules (home/core, packs, ...) so central
      # identity values (username, email, stateVersion) resolve there.
      extraSpecialArgs = inputs // { inherit vars; hostSpec = spec; };
    };
  }
]
