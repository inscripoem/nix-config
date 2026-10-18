#!/usr/bin/env bash
# Update workbuddy, cc-switch, siyuan, ww-manager, notion-electron,
# zcode-cli and dsh-tui-launcher to their latest upstream versions, update
# wechat, and align the qq version pin with the linuxqq-wayland-fix input.
# Usage:
#   ./update-versions.sh [--dry-run] [--only=<names>]
#
# Options:
#   --dry-run              Show what would change without modifying files.
#   --only=<names>         Comma-separated subset of
#                          {workbuddy,cc-switch,siyuan,ww-manager,notion-electron,zcode-cli,dsh-tui-launcher,wechat,qq}.
#                          `notion` is accepted as an alias for notion-electron.
#                          Defaults to all nine.
#
# Requirements: curl, jq, git, nix (flakes), nix-prefetch-url, sed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
ONLY=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --only=*)
      ONLY="${arg#--only=}"
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

# Latest version of a project on PyPI; `project` is the PyPI project name.
pypi_latest_version() {
  local project="$1" version=""
  version=$(curl -sf --max-time 10 "https://pypi.org/pypi/${project}/json" | jq -r '.info.version') || true
  if [[ -z "$version" || "$version" == "null" ]]; then
    echo "ERROR: PyPI lookup failed for ${project}." >&2
    exit 1
  fi
  echo "$version"
}

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

# ── dsh-tui-launcher ─────────────────────────────────────────────────

if should_update "dsh-tui-launcher"; then
  echo ""
  echo "==> Checking dsh-tui-launcher ..."
  # The launcher pin pairs with the KERNEL through the plugin's declared
  # @deepseek-ai/* peerDependencies: `dsh plugin add` hard-gates on them,
  # and the flake's own bundle pairing does not extend to npm (0.15.0
  # targets kernel 0.2.0-rc.2 and is rejected by 0.2.1-rc.2). So resolve
  # the kernel version from the flake.lock rev, then pick the NEWEST
  # stable launcher release whose requirements accept it — blind "latest"
  # would break first bootstraps. Constraint match is exact-term over the
  # "||" branches (the registry enumerates allowed workspace versions
  # explicitly); a caret branch merely spanning the kernel counts as
  # no-match, which errs toward the older, safe pin.
  dt_lock_rev=$(jq -r '.nodes["deepseek-harness"].locked.rev // empty' "$REPO_ROOT/flake.lock")
  if [[ -z "$dt_lock_rev" ]]; then
    echo "    ERROR: deepseek-harness missing from flake.lock (run: nix flake lock)." >&2
    exit 1
  fi
  dt_kernel=$(nix --extra-experimental-features 'nix-command flakes' eval \
    --raw "github:moraxyc/deepseek-harness.nix/${dt_lock_rev}#packages.x86_64-linux.dsh.version" 2>/dev/null) || true
  if [[ -z "$dt_kernel" ]]; then
    echo "    ERROR: could not resolve the kernel version from the locked deepseek-harness rev ${dt_lock_rev:0:7}." >&2
    exit 1
  fi

  # The full packument is off-limits here: npm serves it with unescaped
  # control characters in the readme, which jq refuses to parse (and the
  # cache makes that intermittent). Version list comes from `npm view`,
  # and each candidate's contract from its clean per-version document.
  dt_versions=$(npm view @deepseek-harness-tui/dsh-tui versions --json 2>/dev/null \
    | jq -r 'if type == "array" then .[] else . end' 2>/dev/null)
  if [[ -z "$dt_versions" ]]; then
    echo "    ERROR: could not list dsh-tui versions from the npm registry." >&2
    exit 1
  fi

  dt_nix="$REPO_ROOT/pkgs/dsh-tui-launcher.nix"
  dt_current=$(grep 'version = ' "$dt_nix" | head -1 | grep -oP '[\d.]+')

  # Newest-first stable releases; accept the first whose @deepseek-ai/*
  # peerDependencies all take the pinned kernel. The scan is bounded so a
  # long incompatible tail cannot turn into an unbounded request series.
  dt_target=""
  dt_scanned=0
  for dt_v in $(echo "$dt_versions" | grep -v -- '-' | sort -rV); do
    dt_scanned=$((dt_scanned + 1))
    [[ $dt_scanned -gt 20 ]] && break
    if curl -sf --max-time 10 "https://registry.npmjs.org/@deepseek-harness-tui/dsh-tui/$dt_v" \
      | jq -e --arg kernel "$dt_kernel" '
          [.peerDependencies // {} | to_entries[]
            | select(.key | startswith("@deepseek-ai/dsh-"))
            | .value] as $reqs
          | ($reqs | length) > 0
          and ([$reqs[]
            | select((split(" || ") | index($kernel)) != null)] | length)
            == ($reqs | length)' >/dev/null 2>&1; then
      dt_target=$dt_v
      break
    fi
  done

  if [[ -z "$dt_target" ]]; then
    dt_latest=$(npm view @deepseek-harness-tui/dsh-tui dist-tags.latest 2>/dev/null || echo unknown)
    echo "    ERROR: no dsh-tui release accepts the pinned kernel $dt_kernel (npm latest: $dt_latest)." >&2
    echo "          Update the deepseek-harness flake input to a kernel the newer" >&2
    echo "          launchers accept, then re-run this updater." >&2
    exit 1
  fi

  echo "    kernel  : $dt_kernel (from flake.lock)"
  echo "    current : $dt_current"
  echo "    target  : $dt_target (newest release accepting this kernel)"

  if [[ "$dt_target" == "$dt_current" ]]; then
    echo "    up to date."
  else
    older=$(printf '%s\n%s\n' "$dt_target" "$dt_current" | sort -V | head -1)
    if [[ "$older" == "$dt_target" ]]; then
      echo "    skip: newest compatible ($dt_target) is older than local ($dt_current)."
    else
      echo "    updating ..."
      if [[ "$DRY_RUN" == false ]]; then
        dt_url="https://registry.npmjs.org/@deepseek-harness-tui/dsh-tui/-/dsh-tui-${dt_target}.tgz"

        echo "    prefetching launcher tarball ..."
        dt_hash=$(prefetch_hash "$dt_url")

        update_nix_field "$dt_nix" "version" "$dt_target"
        update_nix_field "$dt_nix" "hash" "$dt_hash"

        echo "    done: $dt_current → $dt_target"
        changed=true
      else
        echo "    [dry-run] would update to $dt_target"
      fi
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
