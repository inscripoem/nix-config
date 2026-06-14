{
  programs.fish = {
    enable = true;
    shellAliases = {
      nhs = "nh os switch -- --show-trace";
      # Cache-only rebuild: --max-jobs 0 forbids local builds, so any cache
      # miss aborts before mutating the system. Pair with `git checkout
      # flake.lock` to roll back a `nix flake update` that outran upstream
      # binary caches.
      nhsc = "nh os switch -- --show-trace --max-jobs 0";
      ze = "zeditor .";
    };
  };
}
