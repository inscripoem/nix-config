# Declarative WiFi connection profiles. The site name defaults to
# HKHomeNet and is configurable via
# `modules.capabilities.wifi-profiles.siteName`.
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
#     actually roam onto HKHomeNet need them. Servers on fixed
#     Ethernet links and WSL (nutshell — its network is handed down
#     by Windows) do not, and they must not be forced to consume
#     the wifi.yaml SOPS secret they cannot decrypt.
#   - Making it opt-in means unrelated hosts never trigger the
#     `setupSecrets` activation snippet for wifi.yaml (which fails
#     when the host's age key is not a recipient in .sops.yaml).
#
# SOPS key naming convention (secrets/wifi.yaml):
#   wifi_<siteName>[_5G]_{ssid,psk} — with the default siteName (HKHomeNet):
#   wifi_HKHomeNet_5G_ssid: "my-5ghz-ssid"
#   wifi_HKHomeNet_5G_psk:  "5ghz-password"
#   wifi_HKHomeNet_ssid:    "my-24ghz-ssid"
#   wifi_HKHomeNet_psk:     "24ghz-password"
# Changing siteName requires re-encrypting secrets/wifi.yaml with the
# matching keys, otherwise decryption fails during activation.
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
  # SOPS key prefix; keys in secrets/wifi.yaml follow the
  # wifi_<siteName>[_5G]_{ssid,psk} convention.
  prefix = "wifi_${cfg.siteName}";
in
{
  options.modules.capabilities.wifi-profiles = {
    enable =
      lib.mkEnableOption "declarative HKHomeNet NetworkManager profiles";
    siteName = lib.mkOption {
      type = lib.types.str;
      default = "HKHomeNet";
      description = ''
        Site name used to derive the NetworkManager profile names and the
        SOPS secret keys, which follow the naming convention
        `wifi_<siteName>[_5G]_{ssid,psk}` stored in secrets/wifi.yaml.
        Changing this value requires re-encrypting that file with matching
        keys, otherwise decryption fails during activation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."${prefix}_5G_ssid" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."${prefix}_5G_psk" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."${prefix}_ssid" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };
    sops.secrets."${prefix}_psk" = {
      sopsFile = ../../../secrets/wifi.yaml;
      owner = "root";
      mode = "0400";
    };

    sops.templates."wifi.env" = {
      content = ''
        ${prefix}_5G_ssid=${config.sops.placeholder."${prefix}_5G_ssid"}
        ${prefix}_5G_psk=${config.sops.placeholder."${prefix}_5G_psk"}
        ${prefix}_ssid=${config.sops.placeholder."${prefix}_ssid"}
        ${prefix}_psk=${config.sops.placeholder."${prefix}_psk"}
      '';
      owner = "root";
      mode = "0400";
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [ config.sops.templates."wifi.env".path ];
      profiles = {
        "${cfg.siteName}_5G" = {
          connection = {
            id = "${cfg.siteName}_5G";
            type = "wifi";
            permissions = "";
            autoconnect = true;
            autoconnect-priority = 10;
          };
          wifi = {
            mode = "infrastructure";
            # "$" as a separate concat term: on Nix >= 2.3x `$$` inside a
            # double-quoted string is no longer (literal $ + interpolation).
            ssid = "$" + prefix + "_5G_ssid";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "$" + prefix + "_5G_psk";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
        "${cfg.siteName}" = {
          connection = {
            id = "${cfg.siteName}";
            type = "wifi";
            permissions = "";
            autoconnect = true;
            autoconnect-priority = 10;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "$" + prefix + "_ssid";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "$" + prefix + "_psk";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };
}
