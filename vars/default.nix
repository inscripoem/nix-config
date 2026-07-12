{
  username = "inscripoem";
  fullName = "Brandon Chang";
  email = "inscripoem@example.com";
  sshKeys = [
    (builtins.readFile ../keys/ssh-ed25519.pub)
  ];
  stateVersion = "25.05";

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

  builderClientKeys = [
    (builtins.readFile ../keys/wyse3040-builder-ed25519.pub)
  ];
}