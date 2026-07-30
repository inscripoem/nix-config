# Declarative WiFi connection profiles for HKHomeNet.
#
# This capability is *not* about enabling WiFi hardware or the
# NetworkManager daemon — NM is unconditionally enabled by base
# (see modules/nixos/base/networking.nix) so every host defaults to
# a NM-managed stack (wired + wireless). What lives here is purely
# the site-specific piece: two HKHomeNet .nmconnection profiles and
# the SOPS plumbing that supplies their SSID/PSK.
#
# Why a capability and not part of base:
#   - The profiles are host-specific: only the machines that will
#     actually roam onto HKHomeNet need them. Servers on a fixed
#     Ethernet link (wyse3040) and WSL (nutshell — its network is
#     handed down by Windows) do not, and they must not be forced
#     to consume the wifi.yaml SOPS secret they cannot decrypt.
#   - Making it opt-in means unrelated hosts never trigger the
#     `setupSecrets` activation snippet for wifi.yaml (which fails
#     when the host's age key is not a recipient in .sops.yaml).
#
# Schema (secrets/wifi.yaml):
#   wifi_HKHomeNet_5G_ssid: "my-5ghz-ssid"
#   wifi_HKHomeNet_5G_psk:  "5ghz-password"
#   wifi_HKHomeNet_ssid:    "my-24ghz-ssid"
#   wifi_HKHomeNet_psk:     "24ghz-password"
#
# Why a *system* connection (`permissions = ""`): without it NM
# stores the PSK in KWallet/gnome-keyring, which is only unlocked
# at user login via PAM. That means no network until someone types
# a password — and no network means no SSH, no Moonlight, no
# remote recovery. A system connection decouples networking from
# user login.
#
# See docs/secrets.md for the SOPS setup and docs/remote-desktop.md
# for how this enables pre-login remote access.

{ config, lib, ... }:
let
  cfg = config.modules.capabilities.wifi-profiles;
in
{
  options.modules.capabilities.wifi-profiles.enable =
    lib.mkEnableOption "declarative HKHomeNet NetworkManager profiles";

  config = lib.mkIf cfg.enable {
    sops.secrets."wifi_HKHomeNet_5G_ssid" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."wifi_HKHomeNet_5G_psk" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."wifi_HKHomeNet_ssid" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."wifi_HKHomeNet_psk" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };

    sops.templates."wifi.env" = {
      content = ''
        wifi_HKHomeNet_5G_ssid=${config.sops.placeholder."wifi_HKHomeNet_5G_ssid"}
        wifi_HKHomeNet_5G_psk=${config.sops.placeholder."wifi_HKHomeNet_5G_psk"}
        wifi_HKHomeNet_ssid=${config.sops.placeholder."wifi_HKHomeNet_ssid"}
        wifi_HKHomeNet_psk=${config.sops.placeholder."wifi_HKHomeNet_psk"}
      '';
      owner = "root";
      mode = "0400";
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [ config.sops.templates."wifi.env".path ];
      profiles = {
        "HKHomeNet_5G" = {
          connection = {
            id = "HKHomeNet_5G";
            type = "wifi";
            permissions = "";
            autoconnect = true;
            autoconnect-priority = 10;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "$wifi_HKHomeNet_5G_ssid";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "$wifi_HKHomeNet_5G_psk";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
        "HKHomeNet" = {
          connection = {
            id = "HKHomeNet";
            type = "wifi";
            permissions = "";
            autoconnect = true;
            autoconnect-priority = 10;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "$wifi_HKHomeNet_ssid";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "$wifi_HKHomeNet_psk";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };
}
