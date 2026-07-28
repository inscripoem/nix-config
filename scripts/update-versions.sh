#!/usr/bin/env bash
# Update trae-cn, cc-switch, siyuan and ww-manager to their latest upstream
# versions.
# Usage:
#   ./update-versions.sh [--dry-run] [--only=<names>] [--trae-version=<X.Y.Z>]
#
# Options:
#   --dry-run              Show what would change without modifying files.
#   --only=<names>         Comma-separated subset of
#                          {trae-cn,cc-switch,siyuan,ww-manager}.
#                          Defaults to all four.
#   --trae-version=<ver>   Skip the trae-cn `latest` API and pin the given
#                          version directly. Only meaningful when trae-cn is
#                          in the selected set.
#
# Requirements: curl, jq, nix-prefetch-url, sed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
ONLY=""
TRAE_VERSION_OVERRIDE=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --only=*)
      ONLY="${arg#--only=}"
      ;;
    --trae-version=*)
      TRAE_VERSION_OVERRIDE="${arg#--trae-version=}"
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

should_update() {
  local name="$1"
  if [[ -z "$ONLY" ]]; then
    return 0
  fi
  local IFS=,
  for item in $ONLY; do
    [[ "$item" == "$name" ]] && return 0
  done
  return 1
}

if [[ -n "$TRAE_VERSION_OVERRIDE" ]] && ! should_update "trae-cn"; then
  echo "ERROR: --trae-version given but trae-cn is not in --only=$ONLY" >&2
  exit 2
fi

changed=false

# ── helpers ──────────────────────────────────────────────────────────

prefetch_hash() {
  local url="$1"
  local raw
  raw=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null | tail -1)
  nix hash to-sri --extra-experimental-features nix-command "sha256:$raw" 2>/dev/null | tail -1
}

update_nix_field() {
  local file="$1" field="$2" new_value="$3"
  # Matches:   field = "..."
  sed -i "s|${field} = \".*\"|${field} = \"${new_value}\"|" "$file"
}

# ── trae-cn ──────────────────────────────────────────────────────────

if should_update "trae-cn"; then
  echo "==> Checking trae-cn ..."
  trae_nix="$REPO_ROOT/pkgs/trae-cn.nix"
  trae_current=$(grep 'version = ' "$trae_nix" | head -1 | grep -oP '[\d.]+')

  if [[ -n "$TRAE_VERSION_OVERRIDE" ]]; then
    trae_version="$TRAE_VERSION_OVERRIDE"
    trae_url="https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/${trae_version}/linux/Trae_CN-linux-x64.deb"
    echo "    (manual override)"
  else
    trae_json=$(curl -sf "https://api.trae.com.cn/icube/api/v1/native/version/trae/cn/latest")
    trae_version=$(echo "$trae_json" | jq -r '.data.manifest.linux.version')
    trae_url=$(echo "$trae_json" | jq -r '.data.manifest.linux.download[0]."x64.deb"')
  fi

  echo "    current : $trae_current"
  echo "    target  : $trae_version"

  # Version gate: in auto mode (no manual override), refuse to downgrade so a
  # lagging `latest` API cannot roll back a manual bump. Manual override is
  # always honoured (explicit intent, useful for rollback).
  skip_trae=false
  if [[ -z "$TRAE_VERSION_OVERRIDE" && "$trae_version" != "$trae_current" ]]; then
    older=$(printf '%s\n%s\n' "$trae_version" "$trae_current" | sort -V | head -1)
    if [[ "$older" == "$trae_version" ]]; then
      echo "    skip: API version ($trae_version) is older than local ($trae_current)."
      echo "          Use --trae-version=$trae_version to force downgrade."
      skip_trae=true
    fi
  fi

  if [[ "$skip_trae" == true ]]; then
    :
  elif [[ "$trae_version" == "$trae_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      trae_hash=$(prefetch_hash "$trae_url")
      # Update URL template: Trae%20CN → Trae_CN (matches API response)
      sed -i 's|Trae%20CN-linux-x64\.deb|Trae_CN-linux-x64.deb|' "$trae_nix"
      update_nix_field "$trae_nix" "version" "$trae_version"
      update_nix_field "$trae_nix" "hash" "$trae_hash"
      echo "    done: $trae_current → $trae_version"
      changed=true
    else
      echo "    [dry-run] would update to $trae_version"
    fi
  fi
fi

# ── cc-switch ────────────────────────────────────────────────────────

if should_update "cc-switch"; then
  echo ""
  echo "==> Checking cc-switch ..."
  if command -v gh &>/dev/null; then
    cc_version=$(gh api repos/farion1231/cc-switch/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      cc_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/farion1231/cc-switch/releases/latest" || true)
    else
      cc_json=$(curl -sf --max-time 10 "https://api.github.com/repos/farion1231/cc-switch/releases/latest" || true)
    fi
    if [[ -z "$cc_json" ]]; then
      echo "    ERROR: Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
      exit 1
    fi
    if echo "$cc_json" | jq -e '.message' >/dev/null 2>&1; then
      echo "    ERROR: GitHub API request failed: $(echo "$cc_json" | jq -r '.message')"
      echo "    Try again later, set GITHUB_TOKEN, or install gh CLI."
      exit 1
    fi
    cc_version=$(echo "$cc_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  cc_nix="$REPO_ROOT/pkgs/cc-switch.nix"
  cc_current=$(grep 'version = ' "$cc_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $cc_current"
  echo "    latest  : $cc_version"

  if [[ "$cc_version" == "$cc_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      x64_url="https://github.com/farion1231/cc-switch/releases/download/v${cc_version}/CC-Switch-v${cc_version}-Linux-x86_64.deb"
      arm64_url="https://github.com/farion1231/cc-switch/releases/download/v${cc_version}/CC-Switch-v${cc_version}-Linux-arm64.deb"

      echo "    prefetching x86_64 ..."
      x64_hash=$(prefetch_hash "$x64_url")
      echo "    prefetching aarch64 ..."
      arm64_hash=$(prefetch_hash "$arm64_url")

      update_nix_field "$cc_nix" "version" "$cc_version"

      # Update x86_64 hash (first occurrence after x86_64 URL)
      sed -i "/x86_64\.deb/{n;s|hash = \".*\"|hash = \"${x64_hash}\"|;}" "$cc_nix"
      # Update aarch64 hash (first occurrence after arm64 URL)
      sed -i "/arm64\.deb/{n;s|hash = \".*\"|hash = \"${arm64_hash}\"|;}" "$cc_nix"

      echo "    done: $cc_current → $cc_version"
      changed=true
    else
      echo "    [dry-run] would update to $cc_version"
    fi
  fi
fi

# ── siyuan ───────────────────────────────────────────────────────────

if should_update "siyuan"; then
  echo ""
  echo "==> Checking siyuan ..."
  if command -v gh &>/dev/null; then
    siyuan_version=$(gh api repos/siyuan-note/siyuan/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      siyuan_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/siyuan-note/siyuan/releases/latest" || true)
    else
      siyuan_json=$(curl -sf --max-time 10 "https://api.github.com/repos/siyuan-note/siyuan/releases/latest" || true)
    fi
    if [[ -z "$siyuan_json" ]]; then
      echo "    ERROR: Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
      exit 1
    fi
    if echo "$siyuan_json" | jq -e '.message' >/dev/null 2>&1; then
      echo "    ERROR: GitHub API request failed: $(echo "$siyuan_json" | jq -r '.message')"
      echo "    Try again later, set GITHUB_TOKEN, or install gh CLI."
      exit 1
    fi
    siyuan_version=$(echo "$siyuan_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  siyuan_nix="$REPO_ROOT/pkgs/siyuan.nix"
  siyuan_current=$(grep 'version = ' "$siyuan_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $siyuan_current"
  echo "    latest  : $siyuan_version"

  if [[ "$siyuan_version" == "$siyuan_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      sums_url="https://github.com/siyuan-note/siyuan/releases/download/v${siyuan_version}/SHA256SUMS.txt"
      x64_asset="siyuan-${siyuan_version}-linux.deb"
      arm64_asset="siyuan-${siyuan_version}-linux-arm64.deb"

      echo "    fetching SHA256SUMS.txt ..."
      sums=$(curl -sfL --max-time 10 "$sums_url")
      if [[ -z "$sums" ]]; then
        echo "    ERROR: Failed to fetch $sums_url"
        exit 1
      fi

      x64_raw=$(echo "$sums" | awk -v f="$x64_asset" '$2==f || $2=="*"f {print $1}')
      arm64_raw=$(echo "$sums" | awk -v f="$arm64_asset" '$2==f || $2=="*"f {print $1}')

      if [[ -z "$x64_raw" || -z "$arm64_raw" ]]; then
        echo "    ERROR: Could not find hashes for $x64_asset / $arm64_asset in SHA256SUMS.txt"
        exit 1
      fi

      x64_hash=$(nix hash to-sri --extra-experimental-features nix-command "sha256:$x64_raw" 2>/dev/null | tail -1)
      arm64_hash=$(nix hash to-sri --extra-experimental-features nix-command "sha256:$arm64_raw" 2>/dev/null | tail -1)

      echo "    prefetching source tree (fetchFromGitHub v${siyuan_version}) ..."
      src_hash=$(nix --extra-experimental-features 'nix-command flakes' flake prefetch --json "github:siyuan-note/siyuan/v${siyuan_version}" 2>/dev/null | jq -r '.hash')
      if [[ -z "$src_hash" || "$src_hash" == "null" ]]; then
        echo "    ERROR: nix flake prefetch failed for github:siyuan-note/siyuan/v${siyuan_version}"
        exit 1
      fi

      update_nix_field "$siyuan_nix" "version" "$siyuan_version"

      # src tree hash (fetchFromGitHub) — the first `hash = "..."` line, sits
      # inside srcTag near the top of siyuan.nix.
      sed -i "0,/hash = \".*\"/{s|hash = \".*\"|hash = \"${src_hash}\"|}" "$siyuan_nix"

      # .deb hashes for x86_64 and aarch64 (unchanged pattern).
      sed -i "/siyuan-\${version}-linux\.deb/{n;s|hash = \".*\"|hash = \"${x64_hash}\"|;}" "$siyuan_nix"
      sed -i "/siyuan-\${version}-linux-arm64\.deb/{n;s|hash = \".*\"|hash = \"${arm64_hash}\"|;}" "$siyuan_nix"

      # vendorHash: reset to zero-hash so the next `nix build` will fail with the
      # correct one. We probe automatically and copy it back in.
      zero_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      sed -i "s|vendorHash = \".*\"|vendorHash = \"${zero_hash}\"|" "$siyuan_nix"
      echo "    probing vendorHash (this triggers one build attempt that is expected to fail) ..."
      vendor_probe_output=$(nix --extra-experimental-features 'nix-command flakes' build \
        --no-link --no-warn-dirty \
        --impure --expr \
        "let f = builtins.getFlake (toString \"$REPO_ROOT\"); m = f.nixosConfigurations.briefcase.config.home-manager.users.inscripoem.home.packages; in builtins.head (builtins.filter (p: p.pname or \"\" == \"siyuan\") m)" \
        2>&1 || true)
      vendor_hash=$(echo "$vendor_probe_output" | awk '/got:/{print $2; exit}')
      if [[ -z "$vendor_hash" ]]; then
        echo "    ERROR: could not extract vendorHash from probe output. Last 20 lines:"
        echo "$vendor_probe_output" | tail -20
        exit 1
      fi
      sed -i "s|vendorHash = \".*\"|vendorHash = \"${vendor_hash}\"|" "$siyuan_nix"

      echo "    done: $siyuan_current → $siyuan_version"
      changed=true
    else
      echo "    [dry-run] would update to $siyuan_version"
    fi
  fi
fi

# ── ww-manager ───────────────────────────────────────────────────────

if should_update "ww-manager"; then
  echo ""
  echo "==> Checking ww-manager ..."
  ww_json=$(curl -sf --max-time 10 "https://pypi.org/pypi/ww-manager/json" || true)
  if [[ -z "$ww_json" ]]; then
    echo "    ERROR: Failed to reach PyPI JSON API for ww-manager."
    exit 1
  fi
  ww_version=$(echo "$ww_json" | jq -r '.info.version')
  if [[ -z "$ww_version" || "$ww_version" == "null" ]]; then
    echo "    ERROR: could not extract .info.version from PyPI response."
    exit 1
  fi

  ww_nix="$REPO_ROOT/pkgs/ww-manager.nix"
  ww_current=$(grep 'version = ' "$ww_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $ww_current"
  echo "    latest  : $ww_version"

  if [[ "$ww_version" == "$ww_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      ww_url="https://pypi.io/packages/source/w/ww-manager/ww_manager-${ww_version}.tar.gz"
      ww_hash=$(prefetch_hash "$ww_url")
      update_nix_field "$ww_nix" "version" "$ww_version"
      update_nix_field "$ww_nix" "hash" "$ww_hash"
      echo "    done: $ww_current → $ww_version"
      changed=true
    else
      echo "    [dry-run] would update to $ww_version"
    fi
  fi
fi

# ── summary ──────────────────────────────────────────────────────────

echo ""
if [[ "$changed" == true ]]; then
  echo "Done."
elif [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. No files changed."
else
  echo "Everything is up to date."
fi
