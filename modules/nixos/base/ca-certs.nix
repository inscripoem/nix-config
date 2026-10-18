{ pkgs, ... }:

{
  # Upstream OpenSSL builds (e.g. python-build-standalone used by uv) hardcode
  # the FHS default trust store at /etc/ssl/cert.pem and expect hash-symlinked
  # capath in /etc/ssl/certs; NixOS provides neither, so their HTTPS fails.
  # Same bundle the system ca-certificates.crt already points to.
  environment.etc."ssl/cert.pem".source =
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
}
