final: prev: {
  harmonyos-sans = final.callPackage ./harmonyos-sans.nix { };
  siyuan = final.callPackage ./siyuan.nix { };
  workbuddy = final.callPackage ./workbuddy.nix { };
  "cc-switch" = final.callPackage ./cc-switch.nix { };
  magpie = final.callPackage ./magpie.nix { };
  notion-electron = final.callPackage ./notion-electron.nix { };
  zcode-cli = final.callPackage ./zcode-cli.nix { };
  glances = final.callPackage ./glances.nix { originalGlances = prev.glances; };
  dsh-tui-launcher = final.callPackage ./dsh-tui-launcher.nix { };
  ene-fanctl = final.callPackage ./ene-fanctl.nix { };

  # atuin 18.23.0's e2e tests are pty/timing-sensitive and hang in the
  # darwin build sandbox, which is why hydra publishes no darwin binary:
  # - e2e_capture's filtered_commands_leave_no_captured_output times out.
  # - every e2e_pty test of the bash+preexec fixture ("setup_2_tests_shells_
  #   bash_preexec_toml") hangs on "waiting for shell session ID" while the
  #   blesh/fish/zsh fixtures pass. --skip matches substrings, so one entry
  #   drops the whole fixture. Extend nixpkgs' own sandbox-incompatible
  #   checkFlags skip list, darwin-only so Linux hosts keep their hydra hits.
  atuin =
    if prev.stdenv.hostPlatform.isDarwin then
      prev.atuin.overrideAttrs (old: {
        checkFlags = (old.checkFlags or [ ]) ++ [
          "--skip=filtered_commands_leave_no_captured_output"
          "--skip=setup_2_tests_shells_bash_preexec_toml"
        ];
      })
    else
      prev.atuin;

  # nixpkgs marks gtk2 broken as part of its removal, but Lutris 0.5.22
  # still lists it in the FHS multiPkgs for legacy games. Rebuild the same
  # FHS arguments without that single dependency instead of globally
  # unbreaking gtk2. Remove this override once Lutris drops gtk2.
  lutris =
    let
      args = prev.lutris.passthru.args;
      withoutGtk2 = packageSet:
        builtins.filter (p: (p.pname or "") != "gtk+") (args.multiPkgs packageSet);
    in
    prev.buildFHSEnv (args // { multiPkgs = withoutGtk2; });

  ww-manager = final.callPackage ./ww-manager.nix { };
}
