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
      # Expose vars to HM modules (home/core, packs, ...) so central
      # identity values (username, email, stateVersion) resolve there.
      extraSpecialArgs = inputs // { inherit vars; };
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
    {
      nixpkgs.overlays = [
        (import ../pkgs)
        # netcatty - upstream's own flake packaging, exposed as pkgs.netcatty.
        # Lives here (not pkgs/) because the source is a flake input and this
        # is the only overlay with inputs in scope: HM sharedModules don't
        # receive extraSpecialArgs, so pack modules can't consume
        # inputs.netcatty directly. Flag wrapping happens in
        # home/packs/remote.nix, which owns the passwordStore arg.
        (final: prev: {
          # netcatty - upstream's own flake packaging (nix/package.nix),
          # exposed as pkgs.netcatty. Lives here (not pkgs/) because the
          # source is a flake input and this is the only overlay with inputs
          # in scope: HM sharedModules don't receive extraSpecialArgs, so
          # pack modules can't consume inputs.netcatty directly. The
          # appimageTools shim aliases upstream's deprecated extractType2
          # call back to extract (see flake.nix); callPackage drops it
          # silently once upstream renames to the new API.
          netcatty = final.callPackage "${inputs.netcatty}/nix/package.nix" {
            appimageTools = final.appimageTools // {
              extractType2 = final.appimageTools.extract;
            };
          };
        })
      ];
    }
    hmBlock
  ]
  ++ extraConfigModule
  ++ (spec.extraModules or [ ])
