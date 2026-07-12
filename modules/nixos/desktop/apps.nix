# Desktop-only applications that have no reason to exist on headless hosts.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kdePackages.kate
  ];
}
