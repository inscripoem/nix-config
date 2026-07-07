#!/usr/bin/env bash
# Update trae-cn and cc-switch to their latest upstream versions.
# Usage: ./update-versions.sh [--dry-run]
#
# Requirements: curl, jq, nix-prefetch-url, sed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

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

echo "==> Checking trae-cn ..."
trae_json=$(curl -sf "https://api.trae.com.cn/icube/api/v1/native/version/trae/cn/latest")
trae_version=$(echo "$trae_json" | jq -r '.data.manifest.linux.version')
trae_url=$(echo "$trae_json" | jq -r '.data.manifest.linux.download[0]."x64.deb"')

trae_nix="$REPO_ROOT/home/editors/trae.nix"
trae_current=$(grep 'version = ' "$trae_nix" | head -1 | grep -oP '[\d.]+')

echo "    current : $trae_current"
echo "    latest  : $trae_version"

if [[ "$trae_version" == "$trae_current" ]]; then
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

# ── cc-switch ────────────────────────────────────────────────────────

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

cc_nix="$REPO_ROOT/home/ai/cc-switch.nix"
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

# ── siyuan ───────────────────────────────────────────────────────────

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

siyuan_nix="$REPO_ROOT/home/productivity/siyuan.nix"
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

    update_nix_field "$siyuan_nix" "version" "$siyuan_version"

    sed -i "/siyuan-\${version}-linux\.deb/{n;s|hash = \".*\"|hash = \"${x64_hash}\"|;}" "$siyuan_nix"
    sed -i "/siyuan-\${version}-linux-arm64\.deb/{n;s|hash = \".*\"|hash = \"${arm64_hash}\"|;}" "$siyuan_nix"

    echo "    done: $siyuan_current → $siyuan_version"
    changed=true
  else
    echo "    [dry-run] would update to $siyuan_version"
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
