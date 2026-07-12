# Declarative WiFi via NetworkManager ensureProfiles + SOPS.
#
# The WiFi SSID and PSK live in `secrets/wifi.yaml` (SOPS-encrypted,
# age via the host's SSH ed25519 key — see .sops.yaml). At activation,
# sops-nix decrypts them to /run/secrets/WIFI_SSID and
# /run/secrets/WIFI_PSK; a sops.templates env file passes those into
# oneshot service, which runs `envsubst` to substitute `$WIFI_SSID`
# and `$WIFI_PSK` into the generated .nmconnection before
# `nmcli connection reload`.
#
# Why this exists: without a "system connection" (permissions=""),
# NetworkManager stores the PSK in KWallet/gnome-keyring, which is
# only unlocked when a user logs in via PAM. That means the box has
# NO network until someone physically types a password — and no
# network means no SSH, no Moonlight, no remote recovery at all.
# Storing the PSK as a system connection decouples networking from
# user login, the same way Windows stores WiFi profiles.
#
# See docs/secrets.md for the SOPS setup and docs/remote-desktop.md
# for how this enables pre-login remote access.

{ config, ... }:

{
  sops.secrets."WIFI_SSID" = {
    sopsFile = ../../../secrets/wifi.yaml;
    owner = "root";
    mode = "0400";
  };
  sops.secrets."WIFI_PSK" = {
    sopsFile = ../../../secrets/wifi.yaml;
    owner = "root";
    mode = "0400";
  };
  sops.secrets."WIFI_SSID_24G" = {
    sopsFile = ../../../secrets/wifi.yaml;
    owner = "root";
    mode = "0400";
  };

  # Generate a simple KEY=value env file from the two sops secrets,
  # so ensureProfiles.environmentFiles can envsubst $WIFI_SSID /
  # $WIFI_PSK into the .nmconnection template below.
  sops.templates."wifi.env" = {
    content = ''
      WIFI_SSID=${config.sops.placeholder."WIFI_SSID"}
      WIFI_PSK=${config.sops.placeholder."WIFI_PSK"}
      WIFI_SSID_24G=${config.sops.placeholder."WIFI_SSID_24G"}
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
          # Empty permissions = system-level connection (not tied to a
          # specific user's keyring). This is what makes NetworkManager
          # auto-connect at boot before any user session exists.
          permissions = "";
          autoconnect = true;
          autoconnect-priority = 10;
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$WIFI_SSID";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          method = "auto";
        };
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
          ssid = "$WIFI_SSID_24G";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          method = "auto";
        };
      };
    };
  };
}