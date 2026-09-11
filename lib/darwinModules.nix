{ inputs, vars }:
spec:
[
  spec.hostModule
  ../modules/darwin/base
  inputs.home-manager.darwinModules.home-manager
  {
    users.users.${vars.username}.home = "/Users/${vars.username}";

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "backup";
      users.${vars.username} = import spec.hmEntryPoint;
      extraSpecialArgs = inputs // { hostSpec = spec; };
    };
  }
]
