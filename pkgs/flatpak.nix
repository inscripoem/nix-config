{ flatpak, fetchurl }:

# Fix flatpak 1.18.0 regression where the host environment (containing
# NixOS /nix/store paths) was leaked into flatpak-spawn --sandbox
# sub-sandboxes, causing glycin-based image loaders (JPEG/PNG/etc.) to
# fail with "Loader process exited early" inside Flatpak apps.
# Upstream: https://github.com/flatpak/flatpak/pull/6721
flatpak.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    (fetchurl {
      url = "https://github.com/flatpak/flatpak/pull/6721.patch";
      hash = "sha256:0pdh9z0vnrfczcxvdsyrhw69xn3hfm9zzdka0za08gkgsgvi2ayn";
    })
  ];
})
