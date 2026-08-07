{ vars, inputs }:
spec:
let
  # Resolve class directories from spec.classes.
  classModules = map (c: ../modules/nixos/${c}) (spec.classes or [ ]);

  # Home Manager wiring block — generic settings shared across all hosts.
  hmBlock = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # All pack modules are declared once here so every host only needs to
      # flip `packs.<name>.enable`, mirroring the capability pattern.
      sharedModules = [ ../home/packs ] ++ (spec.hmSharedModules or [ ]);
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
