{
  username = "inscripoem";
  fullName = "Brandon Chang";
  email = "changxuben@gmail.com";
  sshKeys = [
    (builtins.readFile ../keys/ssh-ed25519.pub)
  ];
  stateVersion = "25.05";
  # nix-darwin's system.stateVersion is an integer (current: 6), unlike
  # the string form used by NixOS and Home Manager above.
  darwinStateVersion = 6;

  builders = {
    briefcase = {
      hostName = "briefcase.local";
      sshUser = "nix-builder";
      systems = [ "x86_64-linux" ];
      maxJobs = 8;
      speedFactor = 10;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    };
  };

  # Empty since the wyse3040 builder key was removed with its host
  # (2026-10-29). Kept as a list: remote-builder.nix consumes
  # `vars.builderClientKeys or [ ]`.
  builderClientKeys = [ ];
}