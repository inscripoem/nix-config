{ vars, inputs }:
spec:
let
  inherit (inputs.nixpkgs) lib;

  # Resolve class directories from spec.classes.
  classModules = map (c: ../modules/nixos/${c}) (spec.classes or [ ]);

  # Home Manager wiring block — generic settings shared across all hosts.
  hmBlock = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = spec.hmSharedModules or [ ];
      backupFileExtension = "backup";
      users.${vars.username} = import spec.hmEntryPoint;
      extraSpecialArgs = inputs;
    };
  };

  # Optional NixOS config block from extraConfig (e.g. capability toggles).
  extraConfigModule = if spec ? extraConfig then [ spec.extraConfig ] else [ ];
in
  classModules
  ++ [
    spec.hardwarePath
    ../modules/nixos/base
    ../modules/nixos/capabilities
    inputs.sops-nix.nixosModules.sops
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.aagl.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
    { nixpkgs.overlays = [ (import ../pkgs) ]; }
    hmBlock
  ]
  ++ extraConfigModule
  ++ (spec.extraModules or [ ])
