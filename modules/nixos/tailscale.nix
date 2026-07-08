# System-side Tailscale integration.
#
# Why this lives at the system level (and not under home/):
#   - `services.tailscale` is a NixOS module. It manages the tailscaled
#     systemd unit, installs the `tailscale` CLI into the system profile,
#     creates the `tailscale0` TUN interface, and (with `openFirewall`)
#     punches a hole in the host firewall — none of which home-manager
#     can do.
#   - `useRoutingFeatures` toggles kernel-level knobs (rp_filter on the
#     firewall, net.ipv{4,6}.conf.all.forwarding sysctls), which are
#     strictly system territory and host-specific. It is therefore set
#     per host in hosts/<host>/default.nix instead of here.
#
# Post-rebuild bootstrap (manual, one-off per node):
#   sudo tailscale up
# Optional flags people frequently want:
#   --ssh                      (enable Tailscale SSH on this node)
#   --accept-routes            (consume subnet routes advertised by peers)
#   --exit-node=<peer>         (route public traffic through <peer>)
#   --advertise-exit-node      (offer this host as an exit node;
#                               requires useRoutingFeatures = "server"|"both")
#   --advertise-routes=<cidr>  (subnet router;
#                               requires useRoutingFeatures = "server"|"both")
# These can also be applied declaratively via `services.tailscale.extraSetFlags`
# once we are sure we want them pinned in config.

{ ... }:

{
  services.tailscale = {
    enable = true;
    # Opens UDP 41641 on the host firewall. This is the port tailscaled
    # uses for direct WireGuard traffic; without it, peers fall back to
    # DERP relays, which adds latency. The control-plane HTTPS to
    # login.tailscale.com is outbound-only and never needs an inbound
    # rule.
    openFirewall = true;
  };
}
