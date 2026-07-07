{
  username = "inscripoem";
  fullName = "Brandon Chang";
  email = "inscripoem@example.com";
  sshKeys = [
    (builtins.readFile ../keys/ssh-ed25519.pub)
  ];
  stateVersion = "25.05";
}