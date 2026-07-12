# Declarative WiFi via NetworkManager ensureProfiles + SOPS.
#
# The WiFi SSIDs and PSK live in `secrets/wifi.yaml` (SOPS-encrypted,
# age via host / editor / recovery keys — see .sops.yaml). At activation
# sops-nix decrypts it to /run/secrets/wifi, then a oneshot service
# uses yq to extract values into a flat env file consumed by
# NetworkManager ensureProfiles via envsubst.
#
# Schema (secrets/wifi.yaml):
#   wifi:
#     HKHomeNet_5G:
#       ssid: "my-5ghz-ssid"
#       psk: "5ghz-password"
#     HKHomeNet:
#       ssid: "my-24ghz-ssid"
#       psk: "24ghz-password"
#
# Why a system connection (permissions=""): without it NetworkManager
# stores the PSK in KWallet/gnome-keyring, which is only unlocked at
# user login via PAM. That means no network until someone types a
# password — and no network means no SSH, no Moonlight, no remote
# recovery. A system connection decouples networking from user login.
#
# See docs/secrets.md for the SOPS setup and docs/remote-desktop.md
# for how this enables pre-login remote access.

{ config, pkgs, ... }:

let
  wifiSecret = config.sops.secrets."wifi".path;
in
{
  sops.secrets."wifi" = {
    sopsFile = ../../../secrets/wifi.yaml;
    owner = "root";
    mode = "0400";
  };

  # oneshot: parse nested wifi.yaml → flat env file → trigger nmcli reload.
  systemd.services."wifi-profiles" = {
    description = "Generate WiFi NM profile env from sops secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.yq-go}/bin/yq -o=shell "${wifiSecret}" > /run/wifi.env
      chmod 600 /run/wifi.env
    '';
    serviceConfig.RemainAfterExit = true;
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/run/wifi.env" ];
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
}
