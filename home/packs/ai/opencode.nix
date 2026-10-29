{ config, lib, pkgs, llm-agents, ... }:

let
  cfg = config.packs.ai;
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # OpenCode 2 via llm-agents' opencode2 (official npm @opencode/cli-*
  # builds, vendored with the runtime rpath already fixed). Upstream
  # installs the binary as `opencode2` only so both major lines can
  # coexist on one machine; this pack swaps wholesale, so the bin is
  # renamed back to `opencode`. The joined name carries the upstream
  # version so generation diffs render llm-agents updates as a plain
  # version change (dix pairs custom pname-version names correctly).
  # oh-my-opencode-slim
  # bridges onto this host from the same package it used on v1; its
  # version is pinned in ~/.config/opencode/opencode.json because v2
  # re-resolves unpinned npm plugins on every startup (silent rolling
  # upgrades).
  opencodePkg = pkgs.symlinkJoin {
    pname = "opencode-joined";
    version = agentPkgs.opencode2.version;
    paths = [ agentPkgs.opencode2 ];
    postBuild = ''
      mv $out/bin/opencode2 $out/bin/opencode
    '';
  };
in
{
  options.packs.ai.opencode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "opencode agent CLI";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.opencode.enable {
      home.packages = [ opencodePkg ];
    })
  ];
}
