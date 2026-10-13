#!/usr/bin/env bash
# Update trae-cn, qoder-cn, qoder-cn-ide, workbuddy, cc-switch, siyuan,
# ww-manager, notion-electron, orca-ide and zcode-cli to their latest
# upstream versions, update wechat, and align the qq version pin with the
# linuxqq-wayland-fix input.
# Usage:
#   ./update-versions.sh [--dry-run] [--only=<names>] [--trae-version=<X.Y.Z>]
#
# Options:
#   --dry-run              Show what would change without modifying files.
#   --only=<names>         Comma-separated subset of
#                          {trae-cn,qoder-cn,qoder-cn-ide,workbuddy,cc-switch,siyuan,ww-manager,notion-electron,orca-ide,zcode-cli,wechat,qq}.
#                          `notion` is accepted as an alias for notion-electron.
#                          Defaults to all twelve.
#   --trae-version=<ver>   Skip the trae-cn `latest` API and pin the given
#                          version directly. Only meaningful when trae-cn is
#                          in the selected set.
#
# Requirements: curl, jq, git, nix (flakes), nix-prefetch-url, sed

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
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# Normalize aliases: `notion` → `notion-electron` (the package's pname).
if [[ -n "$ONLY" ]]; then
  IFS=, read -ra items <<< "$ONLY"
  normalized=""
  for item in "${items[@]}"; do
    if [[ "$item" == "notion" ]]; then
      item="notion-electron"
    fi
    normalized+="${normalized:+,}${item}"
  done
  ONLY="$normalized"
fi

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

# Latest release tag of a GitHub repo, leading `v` stripped. Prefers `gh`;
# falls back to the REST API with optional GITHUB_TOKEN. Exits 1 on failure.
github_latest_version() {
  local repo="$1" version=""
  if command -v gh &>/dev/null; then
    version=$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//') || true
  else
    local auth=() json
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    json=$(curl -sf --max-time 10 "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest") || true
    if [[ -n "$json" ]] && ! echo "$json" | jq -e '.message' >/dev/null 2>&1; then
      version=$(echo "$json" | jq -r '.tag_name' | sed 's/^v//')
    fi
  fi
  if [[ -z "$version" || "$version" == "null" ]]; then
    echo "ERROR: GitHub API lookup failed for ${repo}. Check your network, set GITHUB_TOKEN, or install gh CLI." >&2
    exit 1
  fi
  echo "$version"
}

# Read the Version field of a remote .deb without downloading it: a 64 KiB
# range request covers the ar header plus the control.tar member; unpack
# ./control and strip the epoch prefix.
deb_version_of() {
  local url="$1" tmp csize
  tmp=$(mktemp)
  if ! curl -sf --max-time 30 -r 0-65535 "$url" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  # ar layout: 8B magic; debian-binary header (60B) + 4B data; the control
  # member header starts at offset 72, its size field at offset 120 (10B).
  csize=$(dd if="$tmp" bs=1 skip=120 count=10 2>/dev/null | tr -d ' ')
  dd if="$tmp" bs=1 skip=132 count="$csize" 2>/dev/null \
    | xz -dc 2>/dev/null \
    | tar -xO ./control 2>/dev/null \
    | awk '/^Version:/ { sub(/^Version:[[:space:]]*/, ""); sub(/^[0-9]+:/, ""); print; exit }'
  rm -f "$tmp"
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
    trae_url=$(echo "$trae_json" | jq -r '.data.manifest.linux.download[0]."x64.deb"')
    # The `latest` API no longer exposes a version field; the version is
    # embedded in the download URL: .../releases/stable/<version>/linux/...
    trae_version=$(echo "$trae_url" | grep -oP 'stable/\K[0-9.]+')
    if [[ -z "$trae_version" ]]; then
      echo "    ERROR: could not extract version from API download URL." >&2
      exit 1
    fi
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
      update_nix_field "$trae_nix" "version" "$trae_version"
      update_nix_field "$trae_nix" "hash" "$trae_hash"
      echo "    done: $trae_current → $trae_version"
      changed=true
    else
      echo "    [dry-run] would update to $trae_version"
    fi
  fi
fi

# ── qoder-cn-ide ─────────────────────────────────────────────────────
# Version source is the official changelog repo's tags. Verified 2026-10-09:
# versioned OSS paths are independent stable objects (distinct crc per
# version), but the changelog lags the CDN — floating `lastest` already
# served 1.32.2 while the newest tag was 1.32.0, so updates land late.
# Bucket versioning is on, so a silent same-version re-upload would still
# only surface as a build-time hash mismatch, never as a wrong artifact.

if should_update "qoder-cn-ide"; then
  echo ""
  echo "==> Checking qoder-cn-ide ..."
  qoder_nix="$REPO_ROOT/pkgs/qoder.nix"
  qoder_current=$(grep 'version = ' "$qoder_nix" | head -1 | grep -oP '[\d.]+')
  qoder_version=$(github_latest_version "QoderAI/changelog-zh_CN")
  qoder_url="https://qoder-ide-cn.oss-cn-hangzhou.aliyuncs.com/qoder/release/${qoder_version}/qoder-cn-ide_amd64.deb"

  echo "    current : $qoder_current"
  echo "    target  : $qoder_version"

  # Version gate: refuse to downgrade so a lagging changelog tag cannot
  # roll back a manual bump.
  skip_qoder=false
  if [[ "$qoder_version" != "$qoder_current" ]]; then
    older=$(printf '%s\n%s\n' "$qoder_version" "$qoder_current" | sort -V | head -1)
    if [[ "$older" == "$qoder_version" ]]; then
      echo "    skip: changelog tag ($qoder_version) is older than local ($qoder_current)."
      skip_qoder=true
    fi
  fi

  if [[ "$skip_qoder" == true ]]; then
    :
  elif [[ "$qoder_version" == "$qoder_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      qoder_hash=$(prefetch_hash "$qoder_url")
      update_nix_field "$qoder_nix" "version" "$qoder_version"
      update_nix_field "$qoder_nix" "hash" "$qoder_hash"
      echo "    done: $qoder_current → $qoder_version"
      changed=true
    else
      echo "    [dry-run] would update to $qoder_version"
    fi
  fi
fi

# ── qoder-cn ─────────────────────────────────────────────────────────
# New-form Qoder desktop app (distinct from qoder-cn-ide). The CDN only
# exposes a floating `latest` object alongside per-version paths, so the
# version is read from the latest deb's control member via a range request.

if should_update "qoder-cn"; then
  echo ""
  echo "==> Checking qoder-cn ..."
  qapp_nix="$REPO_ROOT/pkgs/qoder-cn.nix"
  qapp_current=$(grep 'version = ' "$qapp_nix" | head -1 | grep -oP '[\d.]+')
  qapp_version=$(deb_version_of "https://qoder-app.oss-cn-beijing.aliyuncs.com/qoder-app/releases/latest/Qoder-CN-linux-amd64.deb")
  if [[ -z "$qapp_version" ]]; then
    echo "    ERROR: could not read version from the latest deb's control member." >&2
    exit 1
  fi
  qapp_url="https://qoder-app.oss-cn-beijing.aliyuncs.com/qoder-app/releases/${qapp_version}/Qoder-CN-linux-amd64.deb"

  echo "    current : $qapp_current"
  echo "    target  : $qapp_version"

  # Version gate: refuse to downgrade so a stale floating object cannot
  # roll back a manual bump.
  skip_qapp=false
  if [[ "$qapp_version" != "$qapp_current" ]]; then
    older=$(printf '%s\n%s\n' "$qapp_version" "$qapp_current" | sort -V | head -1)
    if [[ "$older" == "$qapp_version" ]]; then
      echo "    skip: latest deb version ($qapp_version) is older than local ($qapp_current)."
      skip_qapp=true
    fi
  fi

  if [[ "$skip_qapp" == true ]]; then
    :
  elif [[ "$qapp_version" == "$qapp_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      qapp_hash=$(prefetch_hash "$qapp_url")
      update_nix_field "$qapp_nix" "version" "$qapp_version"
      update_nix_field "$qapp_nix" "hash" "$qapp_hash"
      echo "    done: $qapp_current → $qapp_version"
      changed=true
    else
      echo "    [dry-run] would update to $qapp_version"
    fi
  fi
fi

# ── workbuddy ────────────────────────────────────────────────────────
# Tencent CodeBuddy team's agentic desktop workspace. The official update
# API returns JSON {version,url,sha256hash}; the deb filename embeds
# "-<rev>", which pkgs/workbuddy.nix keeps in a separate `rev` field.
# Observed 2026-10-10: the API's sha256hash did NOT match the served
# artifact (stale after a same-version re-upload), so the hash is always
# prefetched from the artifact instead of trusting the API field.

if should_update "workbuddy"; then
  echo ""
  echo "==> Checking workbuddy ..."
  wb_nix="$REPO_ROOT/pkgs/workbuddy.nix"
  wb_current=$(grep 'version = ' "$wb_nix" | head -1 | grep -oP '[\d.]+')
  wb_json=$(curl -sf --max-time 15 "https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb") || true
  wb_version=$(echo "${wb_json:-}" | jq -r '.version // empty' 2>/dev/null)
  wb_url=$(echo "${wb_json:-}" | jq -r '.url // empty' 2>/dev/null)
  if [[ -z "$wb_version" || -z "$wb_url" ]]; then
    echo "    ERROR: could not read .version/.url from the workbuddy update API." >&2
    exit 1
  fi
  wb_rev=$(basename "$wb_url" .deb)
  wb_rev=${wb_rev#WorkBuddy-linux-x64-deb-${wb_version}-}

  echo "    current : $wb_current"
  echo "    target  : $wb_version (rev $wb_rev)"

  # Version gate: refuse to downgrade so a stale API response cannot roll
  # back a manual bump.
  skip_wb=false
  if [[ "$wb_version" != "$wb_current" ]]; then
    older=$(printf '%s\n%s\n' "$wb_version" "$wb_current" | sort -V | head -1)
    if [[ "$older" == "$wb_version" ]]; then
      echo "    skip: API version ($wb_version) is older than local ($wb_current)."
      skip_wb=true
    fi
  fi

  if [[ "$skip_wb" == true ]]; then
    :
  elif [[ "$wb_version" == "$wb_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      echo "    prefetching (~430 MB deb) ..."
      wb_hash=$(prefetch_hash "$wb_url")
      update_nix_field "$wb_nix" "version" "$wb_version"
      update_nix_field "$wb_nix" "rev" "$wb_rev"
      update_nix_field "$wb_nix" "hash" "$wb_hash"
      echo "    done: $wb_current → $wb_version"
      changed=true
    else
      echo "    [dry-run] would update to $wb_version"
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
      # correct one. We probe automatically and copy it back in. The probe
      # targets whichever NixOS host first lists siyuan in its home-manager
      # packages (siyuan is linux-only, so darwin hosts are skipped) —
      # no host name is hardcoded.
      zero_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      sed -i "s|vendorHash = \".*\"|vendorHash = \"${zero_hash}\"|" "$siyuan_nix"
      echo "    probing vendorHash (this triggers one build attempt that is expected to fail) ..."
      vendor_hash=""
      probe_attempt=1
      probe_max_attempts=3
      while [[ "$probe_attempt" -le "$probe_max_attempts" ]]; do
        vendor_probe_output=$(nix --extra-experimental-features 'nix-command flakes' build \
          --no-link --no-warn-dirty \
          --impure --expr "
            let
              f = builtins.getFlake (toString \"$REPO_ROOT\");
              hosts = f.nixosConfigurations;
              pkg = \"siyuan\";
              hasPkg = u: builtins.any (p: (p.pname or \"\") == pkg) (u.home.packages or [ ]);
              hostName = builtins.head (builtins.filter (n:
                builtins.any hasPkg
                  (builtins.attrValues (hosts.\${n}.config.home-manager.users or { }))
              ) (builtins.attrNames hosts));
              users = hosts.\${hostName}.config.home-manager.users;
            in
            builtins.head (builtins.filter (p: (p.pname or \"\") == pkg)
              ((builtins.head (builtins.filter hasPkg (builtins.attrValues users))).home.packages))" \
          2>&1 || true)
        vendor_hash=$(echo "$vendor_probe_output" | awk '/got:/{print $2; exit}')
        [[ -n "$vendor_hash" ]] && break
        # Structural failures cannot be fixed by retrying; fall through to the
        # diagnostics below. Anything else (e.g. proxy.golang.org EOFs) is
        # usually transient — try again.
        if echo "$vendor_probe_output" | grep -qE "doesn't match anything|called on an empty list"; then
          break
        fi
        echo "    probe attempt ${probe_attempt}/${probe_max_attempts} produced no hash; retrying ..."
        probe_attempt=$((probe_attempt + 1))
        sleep 5
      done
      if [[ -z "$vendor_hash" ]]; then
        echo "    ERROR: vendorHash probe failed:"
        if echo "$vendor_probe_output" | grep -q "doesn't match anything"; then
          echo "          A modPostBuild substituteInPlace anchor no longer matches"
          echo "          upstream (most likely the gulu 0644 patch in pkgs/siyuan.nix)."
          echo "          Update the patch anchor for the new version, then re-run."
        elif echo "$vendor_probe_output" | grep -q "called on an empty list"; then
          echo "          No Linux host in this flake installs siyuan via"
          echo "          home-manager, so there is nowhere to probe from."
        fi
        echo "    Last 20 lines of probe output:"
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

# ── notion-electron ─────────────────────────────────────────────────

if should_update "notion-electron"; then
  echo ""
  echo "==> Checking notion-electron ..."
  if command -v gh &>/dev/null; then
    ne_version=$(gh api repos/anechunaev/notion-electron/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      ne_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/anechunaev/notion-electron/releases/latest" || true)
    else
      ne_json=$(curl -sf --max-time 10 "https://api.github.com/repos/anechunaev/notion-electron/releases/latest" || true)
    fi
    if [[ -z "$ne_json" ]]; then
      echo "    ERROR: Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
      exit 1
    fi
    if echo "$ne_json" | jq -e '.message' >/dev/null 2>&1; then
      echo "    ERROR: GitHub API request failed: $(echo "$ne_json" | jq -r '.message')"
      echo "    Try again later, set GITHUB_TOKEN, or install gh CLI."
      exit 1
    fi
    ne_version=$(echo "$ne_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  ne_nix="$REPO_ROOT/pkgs/notion-electron.nix"
  ne_current=$(grep 'version = ' "$ne_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $ne_current"
  echo "    latest  : $ne_version"

  if [[ "$ne_version" == "$ne_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      ne_url="https://github.com/anechunaev/notion-electron/releases/download/v${ne_version}/Notion_Electron-${ne_version}-x86_64.AppImage"

      echo "    prefetching ..."
      ne_hash=$(prefetch_hash "$ne_url")

      update_nix_field "$ne_nix" "version" "$ne_version"
      update_nix_field "$ne_nix" "hash" "$ne_hash"

      echo "    done: $ne_current → $ne_version"
      changed=true
    else
      echo "    [dry-run] would update to $ne_version"
    fi
  fi
fi

# ── orca-ide ─────────────────────────────────────────────────────────

if should_update "orca-ide"; then
  echo ""
  echo "==> Checking orca-ide ..."
  or_version=$(github_latest_version "stablyai/orca")

  or_nix="$REPO_ROOT/pkgs/orca-ide.nix"
  or_current=$(grep 'version = ' "$or_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $or_current"
  echo "    latest  : $or_version"

  if [[ "$or_version" == "$or_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      # The x86_64 AppImage asset carries no version in its filename.
      or_url="https://github.com/stablyai/orca/releases/download/v${or_version}/orca-linux.AppImage"

      echo "    prefetching ..."
      or_hash=$(prefetch_hash "$or_url")

      update_nix_field "$or_nix" "version" "$or_version"
      update_nix_field "$or_nix" "hash" "$or_hash"

      echo "    done: $or_current → $or_version"
      changed=true
    else
      echo "    [dry-run] would update to $or_version"
    fi
  fi
fi

# ── zcode-cli ────────────────────────────────────────────────────────

if should_update "zcode-cli"; then
  echo ""
  echo "==> Checking zcode-cli ..."
  # GitHub releases lag the git tags here (latest release 3.14.3 vs tag
  # v3.15.1), so resolve the highest tag instead of the releases API.
  zc_version=$(
    git ls-remote --tags --refs https://github.com/zai-org/ZCode 'v*' \
      | awk -F/ '{print $3}' | sed 's/^v//' | sort -V | tail -1)
  if [[ -z "$zc_version" ]]; then
    echo "    ERROR: git ls-remote found no tags for zai-org/ZCode." >&2
    exit 1
  fi

  zc_nix="$REPO_ROOT/pkgs/zcode-cli.nix"
  zc_current=$(grep 'version = ' "$zc_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $zc_current"
  echo "    latest  : $zc_version"

  if [[ "$zc_version" == "$zc_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      zc_url="https://github.com/zai-org/ZCode/archive/refs/tags/v${zc_version}.tar.gz"

      echo "    prefetching source ..."
      zc_hash=$(prefetch_hash "$zc_url")

      update_nix_field "$zc_nix" "version" "$zc_version"
      # Two hash lines exist (src + pnpmDeps); anchor each on its preceding
      # line instead of update_nix_field, which would hit both.
      sed -i "/archive\/refs\/tags/{n;s|hash = \".*\"|hash = \"${zc_hash}\"|;}" "$zc_nix"

      echo "    resolving pnpm store hash (downloads the whole lockfile store) ..."
      # The pnpmDeps hash cannot be prefetched: point it at a sentinel and
      # read the got-hash from the failed FOD build.
      sed -i '/fetcherVersion = 4;/{n;s|hash = ".*"|hash = lib.fakeHash|;}' "$zc_nix"
      zc_deps_hash=$(
        nix build --no-link --impure --expr \
          "(((builtins.getFlake \"$REPO_ROOT\").inputs.nixpkgs.legacyPackages.x86_64-linux).extend (import $REPO_ROOT/pkgs/default.nix)).zcode-cli.pnpmDeps" 2>&1 \
          | grep -oP 'got:\s+\Ksha256-[^=]+=' | head -1)
      if [[ -z "$zc_deps_hash" ]]; then
        echo "    ERROR: could not resolve pnpmDeps hash; pkgs/zcode-cli.nix left at version $zc_version with a fakeHash sentinel." >&2
        exit 1
      fi
      sed -i "/fetcherVersion = 4;/{n;s|hash = lib.fakeHash|hash = \"${zc_deps_hash}\"|;}" "$zc_nix"

      echo "    done: $zc_current → $zc_version (src ${zc_hash:0:14}..., deps ${zc_deps_hash:0:14}...)"
      echo "    NOTE: run nix build on the package once to verify the full build."
      changed=true
    else
      echo "    [dry-run] would update to $zc_version"
    fi
  fi
fi

# ── wechat ───────────────────────────────────────────────────────────

if should_update "wechat"; then
  echo ""
  echo "==> Checking wechat ..."
  # Tencent ships no version API and keeps no history on the official CDN;
  # the mirror archive is also the URL pkgs/default.nix actually fetches,
  # so its latest release tag is the single source of truth here.
  wechat_version=$(github_latest_version "Rodert/wechat-linux-versions")

  wechat_nix="$REPO_ROOT/pkgs/default.nix"
  # Invariant: pkgs/default.nix pins exactly one version/hash pair (the
  # wechat overlay), so the global substitutions in update_nix_field and
  # the URL rewrite below touch only wechat's lines.
  wechat_current=$(grep 'version = ' "$wechat_nix" | head -1 | grep -oP '[\d.]+')

  echo "    current : $wechat_current"
  echo "    latest  : $wechat_version"

  if [[ "$wechat_version" == "$wechat_current" ]]; then
    echo "    up to date."
  else
    echo "    updating ..."
    if [[ "$DRY_RUN" == false ]]; then
      wechat_url="https://github.com/Rodert/wechat-linux-versions/releases/download/v${wechat_version}/WeChatLinux_x86_64.AppImage"

      echo "    prefetching (~300 MB AppImage) ..."
      wechat_hash=$(prefetch_hash "$wechat_url")

      update_nix_field "$wechat_nix" "version" "$wechat_version"
      update_nix_field "$wechat_nix" "hash" "$wechat_hash"
      # The download URL embeds the version separately from `version = `.
      sed -i "s|/download/v${wechat_current}/|/download/v${wechat_version}/|" "$wechat_nix"

      echo "    done: $wechat_current → $wechat_version"
      changed=true
    else
      echo "    [dry-run] would update to $wechat_version"
    fi
  fi
fi

# ── qq (pinned nixpkgs input) ────────────────────────────────────────
# qq is pinned (overlay in modules/nixos/desktop/qq-wayland-fix.nix) to
# the nixpkgs rev that linuxqq-wayland-fix tests against, read from the
# fix's own flake.lock. This entry aligns the pin with the fix version
# already recorded in flake.lock; the linuxqq-wayland-fix input itself
# is never touched here (it rides the regular flake update).

if should_update "qq"; then
  echo ""
  echo "==> Checking qq (nixpkgs-qq pin) ..."
  flake_nix="$REPO_ROOT/flake.nix"
  flake_lock="$REPO_ROOT/flake.lock"

  # qq version shipped by an nixpkgs rev (x86_64-linux entry of sources.nix).
  qq_version_at() {
    curl -sf --max-time 30 "https://raw.githubusercontent.com/NixOS/nixpkgs/$1/pkgs/by-name/qq/qq/sources.nix" |
      awk '/x86_64-linux = \{/ { f = 1; next } f && /version = / { sub(/.*version = "/, ""); sub(/".*/, ""); print; exit }' || true
  }

  current_rev=$(grep -oP 'nixpkgs-qq\.url = "github:NixOS/nixpkgs/\K[0-9a-f]{40}' "$flake_nix" || true)
  if [[ -z "$current_rev" ]]; then
    echo "    ERROR: could not read the nixpkgs-qq rev from flake.nix." >&2
    exit 1
  fi

  fix_rev=$(jq -r '.nodes["linuxqq-wayland-fix"].locked.rev // empty' "$flake_lock")
  if [[ -z "$fix_rev" ]]; then
    echo "    ERROR: linuxqq-wayland-fix is missing from flake.lock." >&2
    echo "          Run: nix flake lock   (adds missing lock entries)" >&2
    exit 1
  fi

  target_rev=$(curl -sf --max-time 30 "https://raw.githubusercontent.com/SHORiN-KiWATA/linuxqq-wayland-fix/${fix_rev}/flake.lock" |
    jq -r '.nodes.nixpkgs.locked.rev // empty' || true)
  if [[ -z "$target_rev" ]]; then
    echo "    ERROR: could not read the nixpkgs rev from linuxqq-wayland-fix's" >&2
    echo "          flake.lock (fix rev ${fix_rev:0:7}). Upstream layout changed?" >&2
    exit 1
  fi

  qq_current=$(qq_version_at "$current_rev")
  qq_target=$(qq_version_at "$target_rev")
  if [[ -z "$qq_current" || -z "$qq_target" ]]; then
    echo "    ERROR: could not read qq versions from nixpkgs sources.nix" >&2
    echo "          (pin ${current_rev:0:7}, target ${target_rev:0:7})." >&2
    exit 1
  fi

  echo "    current : $qq_current @ ${current_rev:0:7}"
  echo "    target  : $qq_target @ ${target_rev:0:7}"

  # Version gate: follow the fix's qq version, and refuse to downgrade so
  # a lagging upstream pin cannot roll back a manual bump.
  skip_qq=false
  if [[ "$qq_target" == "$qq_current" ]]; then
    echo "    up to date."
  else
    older=$(printf '%s\n%s\n' "$qq_target" "$qq_current" | sort -V | head -1)
    if [[ "$older" == "$qq_target" ]]; then
      echo "    skip: fix currently pins qq $qq_target, older than local $qq_current."
      skip_qq=true
    fi
  fi

  if [[ "$skip_qq" == true ]]; then
    :
  elif [[ "$qq_target" != "$qq_current" && "$DRY_RUN" == false ]]; then
    echo "    repinning ..."
    sed -i "s|nixpkgs-qq.url = \"github:NixOS/nixpkgs/${current_rev}\"|nixpkgs-qq.url = \"github:NixOS/nixpkgs/${target_rev}\"|" "$flake_nix"
    # Positional input form: `flake lock --update-input` is deprecated.
    # The pin URL targets a fixed rev, so "update" re-resolves to exactly
    # that rev — no risk of picking up a newer nixpkgs.
    nix --extra-experimental-features 'nix-command flakes' flake update --flake "$REPO_ROOT" nixpkgs-qq
    echo "    done: qq $qq_current → $qq_target (pin ${current_rev:0:7} → ${target_rev:0:7})"
    changed=true
  elif [[ "$qq_target" != "$qq_current" ]]; then
    echo "    [dry-run] would repin to ${target_rev:0:7} (qq $qq_target)"
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
