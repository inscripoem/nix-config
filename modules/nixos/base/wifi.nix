# Declarative WiFi via NetworkManager ensureProfiles + SOPS.
#
# Each WiFi network's SSID and PSK live as flat keys in
# `secrets/wifi.yaml` (SOPS-encrypted, age via host / editor /
# recovery keys — see .sops.yaml). At activation sops-nix decrypts
# them and a sops.templates env file passes the values into envsubst
# for the .nmconnection profiles below. No systemd oneshot needed —
# the activation phase runs before any services start.
#
# Schema (secrets/wifi.yaml):
#   wifi_HKHomeNet_5G_ssid: "my-5ghz-ssid"
#   wifi_HKHomeNet_5G_psk:  "5ghz-password"
#   wifi_HKHomeNet_ssid:    "my-24ghz-ssid"
#   wifi_HKHomeNet_psk:     "24ghz-password"
#
# Why a system connection (permissions=""): without it NetworkManager
# stores the PSK in KWallet/gnome-keyring, which is only unlocked at
# user login via PAM. That means no network until someone types a
# password — and no network means no SSH, no Moonlight, no remote
# recovery. A system connection decouples networking from user login.
#
# See docs/secrets.md for the SOPS setup and docs/remote-desktop.md
# for how this enables pre-login remote access.

{ config, ... }:

{
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
}
