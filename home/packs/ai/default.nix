{ config, lib, pkgs, ... }:

let
  cfg = config.packs.ai;
in
{
  imports = [
    ./aichat.nix
    ./opencode.nix
    ./antigravity-cli.nix
    ./ck.nix
    ./claude-code.nix
    ./codex.nix
    ./rtk.nix
    ./zcode.nix
    ./hermes-gateway.nix
    ./workbuddy.nix
    ./orca.nix
    ./dsh.nix
    ./magpie.nix
    ./cc-switch.nix
  ];

  options.packs.ai.enable = lib.mkEnableOption "AI CLI toolchain (aichat + llm-agents.*)";

  config = lib.mkMerge [
    # Sandbox runtime shared by the pack's agents: codex 0.162+ runs its Linux
    # sandbox through bubblewrap (exec'd from PATH; upstream removed the
    # Landlock fallback), and bare CLIs get it from the ambient profile PATH —
    # workbuddy instead prefixes its own wrapped copy.
    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.bubblewrap ];
    })
  ];
}
