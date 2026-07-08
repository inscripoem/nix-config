# Reserved: server host configurations
# Each server will get its own subdirectory:
#   - hosts/servers/srv-a/default.nix
#   - hosts/servers/srv-b/default.nix
# Each will import ../../modules/nixos/server + host-specific config.
{
  # imports = [ ];
}