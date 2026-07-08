# Reserved: server modules
# To be implemented when server hosts are added.
# This directory will contain server-specific NixOS modules:
#   - ssh.nix: SSH hardening (key-only auth, fail2ban, etc.)
#   - firewall.nix: server firewall rules
#   - monitoring.nix: prometheus node exporter, etc.
#   - docker.nix: Docker/container runtime
#   - impermanence.nix: ephemeral root + persistent storage
{
  # imports = [ ];
}