#!/usr/bin/env bash
# Module registration + class usage audit.
#
# The check itself lives in lib/check-registration.nix and is evaluated from
# ground truth: each manifest-style default.nix's real `imports` field and
# the real nixosHosts table (see that file for the design and its fail-loud
# boundaries). This wrapper only evaluates the flake output, prints the
# report and propagates the verdict.
set -euo pipefail
cd "$(dirname "$0")/.."

json=$(nix eval --json --no-warn-dirty .#moduleRegistration 2>&1) || {
  echo "lint-modules: moduleRegistration failed to evaluate:" >&2
  echo "$json" >&2
  exit 1
}

jq -r '
  "module registration:",
  (.modules[] |
    "  \(.dir): \(.candidates | length) candidates — \(if (.missing | length) == 0 then "all reachable" else "MISSING: \(.missing | join(", "))" end)"),
  "class audit:",
  "  claimed:  \(.classes.claimed | join(", "))",
  (if (.classes.reserved | length) > 0
   then "  reserved: \(.classes.reserved | map(.name + " (" + .reason + ")") | join("; "))"
   else empty end),
  (if (.classes.staleReserved | length) > 0
   then "  STALE RESERVED (claimed by a host now — remove from whitelist): \(.classes.staleReserved | join(", "))" else empty end),
  (if (.classes.unused | length) > 0
   then "  UNUSED (unclaimed, not reserved): \(.classes.unused | join(", "))" else empty end),
  (if (.classes.missingDirs | length) > 0
   then "  MISSING DIRS (referenced by a host, no modules/nixos/<dir>): \(.classes.missingDirs | join(", "))" else empty end)
' <<<"$json"

if ! jq -e '.ok' <<<"$json" >/dev/null; then
  echo "lint-modules: FAIL (see findings above)" >&2
  exit 1
fi
