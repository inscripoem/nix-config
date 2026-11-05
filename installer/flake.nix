{
  description = "Headless NixOS installer ISO with SSH access";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Minimal installation CD base
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

        ({ pkgs, ... }: let
          publicKey = builtins.readFile ./keys/ssh-ed25519.pub;
        in {
          # Hostname — reachable as nixseed.local via mDNS
          networking.hostName = "nixseed";

          # `nixos-install` needs the new CLI. The minimal CD profile leaves
          # experimental features off, so it fails with
          # "experimental Nix feature 'flakes' is disabled" until they are on.
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          # Themed GRUB menu breaks on some 2017-era AMI Aptio firmware
          # (observed on a Colorful C.Q1900M): the menu draws, but executing
          # any entry — or pressing `c` or `t` — kills GRUB with no output at
          # all, and the firmware falls through to its built-in EFI Shell.
          # Text mode boots that board fine.
          #
          # The trigger is not pinned down. A disk-installed NixOS whose GRUB
          # uses gfxterm with a background image but no theme also boots there,
          # which points at the theme, but the ISO differs from that config in
          # several ways. Text mode sidesteps the whole graphical path, which
          # is why it is used here rather than a narrower fix.
          #
          # Only the UEFI menu is affected; the legacy isolinux menu is a
          # separate config and is untouched.
          isoImage.forceTextMode = true;

          # SSH for headless access
          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "yes";
          };

          # mDNS so you can reach it without knowing the IP
          services.avahi = {
            enable = true;
            nssmdns4 = true;
            openFirewall = true;
            publish = {
              enable = true;
              addresses = true;
              workstation = true;
            };
          };

          # Root + nixos user both get the same key
          users.users.root.openssh.authorizedKeys.keys = [ publicKey ];
          users.users.nixos.openssh.authorizedKeys.keys = [ publicKey ];

          # Useful tools for the installer environment
          environment.systemPackages = with pkgs; [
            vim
            git
            curl
          ];

          # Firmware for broader hardware support
          hardware.enableRedistributableFirmware = true;
        })
      ];
    };
  };
}
