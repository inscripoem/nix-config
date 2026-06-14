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
