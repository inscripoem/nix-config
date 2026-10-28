#!/usr/bin/env bash
# Update workbuddy, cc-switch, magpie, siyuan, ww-manager, notion-electron,
# zcode-cli, dsh-tui-launcher and ene-fanctl to their latest upstream
# versions, update wechat, and align the qq version pin with the
# linuxqq-wayland-fix input.
# Usage:
#   ./update-versions.sh [--dry-run] [--only=<names>] [--verbose]
# Options:
#   --dry-run       Show what would change without modifying files.
#   --only=<names>  Comma-separated subset of {workbuddy,cc-switch,magpie,
#                   siyuan,ww-manager,notion-electron,zcode-cli,
#                   dsh-tui-launcher,ene-fanctl,wechat,qq}. `notion` is
#                   accepted as an alias for notion-electron. Defaults to
#                   all eleven; unknown names are an error.
#   --verbose       Full per-package detail (the old multi-line format).
#   -h, --help      Show this help.
# Output: one compact status line per package by default —
#   ✓ up to date   ↗ updated   ⊘ skipped (would downgrade)   ⇒ dry-run preview
# All four glyphs come from Maple Mono NF CN's own cmap (verified via
# `fc-list :charset=…`); e.g. ↻ U+21BB is NOT covered and falls back to
# Hack, which renders thin and misaligned — do not reintroduce it.
#   followed by a one-line tally. Colors and the transient in-place
#   "checking" label are TTY-only; piped output is plain lines.
# Requirements: curl, jq, git, nix (flakes), nix-prefetch-url, npm, sed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
ONLY=""
VERBOSE=false

# ── output layer ─────────────────────────────────────────────────────
# One compact status line per package; `--verbose` restores the old
# multi-line format. The transient "  <name> …" label is printed without
# a newline while a package is being checked and rewritten in place
# (TTY only); piped or NO_COLOR output is plain lines. The counters feed
# the final tally.

is_tty=false
if [[ -t 1 ]]; then is_tty=true; fi
use_color=false
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then use_color=true; fi
C_RESET="" C_DIM="" C_GREEN="" C_YELLOW="" C_CYAN="" C_RED=""
if [[ "$use_color" == true ]]; then
  C_RESET=$'\e[0m' C_DIM=$'\e[2m' C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m' C_CYAN=$'\e[36m' C_RED=$'\e[31m'
fi
PENDING=false
n_uptodate=0 n_updated=0 n_skipped=0 n_dry=0

# Print an error line to stderr, clear any pending transient, exit 1.
# Extra arguments become indented continuation lines.
die() {
  if [[ "$is_tty" == true && "$PENDING" == true ]]; then
    printf '\r\033[K'
    PENDING=false
  fi
  printf '  %s✗ ERROR:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
  if [[ $# -gt 1 ]]; then
    shift
    local l
    for l in "$@"; do
      printf '    %s\n' "$l" >&2
    done
  fi
  exit 1
}

# Start a package's check: verbose gets the old header line, a TTY gets
# an in-place label, a pipe gets nothing (the status line says it all).
status_begin() {
  if [[ "$VERBOSE" == true ]]; then
    printf '==> Checking %s ...\n' "$1"
  elif [[ "$is_tty" == true ]]; then
    printf '  %s%s …%s' "$C_DIM" "$1" "$C_RESET"
    PENDING=true
  fi
}

# The four terminal states; each rewrites the transient label in place.
pkg_up() {
  n_uptodate=$((n_uptodate + 1))
  if [[ "$VERBOSE" == true ]]; then
    printf '    up to date.\n'
    return
  fi
  if [[ "$is_tty" == true ]]; then printf '\r\033[K'; fi
  PENDING=false
  printf '  %s✓%s %s%-18s%s %s%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$1" "$C_RESET" "$2" "$C_RESET"
}

pkg_bump() {
  n_updated=$((n_updated + 1))
  if [[ "$VERBOSE" == true ]]; then
    printf '    updating ...\n'
    return
  fi
  if [[ "$is_tty" == true ]]; then printf '\r\033[K'; fi
  PENDING=false
  printf '  %s↗%s %-18s %s\n' "$C_YELLOW" "$C_RESET" "$1" "$2"
}

pkg_skip() {
  n_skipped=$((n_skipped + 1))
  if [[ "$VERBOSE" == true ]]; then
    printf '    skip: %s\n' "$2"
    return
  fi
  if [[ "$is_tty" == true ]]; then printf '\r\033[K'; fi
  PENDING=false
  printf '  %s⊘%s %s%-18s%s %s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$1" "$C_RESET" "$2" "$C_RESET"
}

pkg_dry() {
  n_dry=$((n_dry + 1))
  if [[ "$VERBOSE" == true ]]; then
    printf '    [dry-run] would update: %s\n' "$2"
    return
  fi
  if [[ "$is_tty" == true ]]; then printf '\r\033[K'; fi
  PENDING=false
  printf '  %s⇒%s %-18s %s\n' "$C_CYAN" "$C_RESET" "$1" "$2"
}

# Progress line for slow steps; printed under the ↻ header (compact) or
# as detail lines (verbose). Must be called after pkg_bump/pkg_dry.
note() {
  if [[ "$is_tty" == true && "$PENDING" == true ]]; then
    printf '\r\033[K'
    PENDING=false
  fi
  printf '      %s\n' "$1"
}

# Verbose-only detail line.
vnote() {
  if [[ "$VERBOSE" == true ]]; then
    printf '    %s\n' "$1"
  fi
}

# Terminate a dangling transient label on any exit path (e.g. a
# mid-check failure outside the guarded diagnostics) so the next shell
# prompt does not append to it.
on_exit() {
  if [[ "$is_tty" == true && "$PENDING" == true ]]; then
    printf '\n'
  fi
}
trap on_exit EXIT

# ── arguments ────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --only=*)
      ONLY="${arg#--only=}"
      ;;
    --verbose)
      VERBOSE=true
      ;;
    -h|--help)
      awk 'NR >= 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# Normalize aliases: `notion` → `notion-electron` (the package's pname),
# and reject unknown names so a typo cannot silently check nothing.
KNOWN_PKGS=(workbuddy cc-switch magpie siyuan ww-manager notion-electron
            zcode-cli dsh-tui-launcher ene-fanctl wechat qq)
if [[ -n "$ONLY" ]]; then
  IFS=, read -ra items <<< "$ONLY"
  normalized=""
  for item in "${items[@]}"; do
    if [[ "$item" == "notion" ]]; then
      item="notion-electron"
    fi
    known=false
    for k in "${KNOWN_PKGS[@]}"; do
      if [[ "$item" == "$k" ]]; then
        known=true
        break
      fi
    done
    if [[ "$known" == false ]]; then
      die "unknown package in --only: $item" \
        "known packages: ${KNOWN_PKGS[*]}"
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

SECONDS=0
header="update-versions"
if [[ "$DRY_RUN" == true ]]; then header+=" [dry-run]"; fi
if [[ "$VERBOSE" == true ]]; then header+=" (verbose)"; fi
printf '%s\n' "$header"

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
    die "GitHub API lookup failed for ${repo}. Check your network, set GITHUB_TOKEN, or install gh CLI."
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
  status_begin "workbuddy"
  wb_nix="$REPO_ROOT/pkgs/workbuddy.nix"
  wb_current=$(grep 'version = ' "$wb_nix" | head -1 | grep -oP '[\d.]+')
  wb_json=$(curl -sf --max-time 15 "https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb") || true
  wb_version=$(echo "${wb_json:-}" | jq -r '.version // empty' 2>/dev/null)
  wb_url=$(echo "${wb_json:-}" | jq -r '.url // empty' 2>/dev/null)
  if [[ -z "$wb_version" || -z "$wb_url" ]]; then
    die "could not read .version/.url from the workbuddy update API."
  fi
  wb_rev=$(basename "$wb_url" .deb)
  wb_rev=${wb_rev#WorkBuddy-linux-x64-deb-${wb_version}-}

  vnote "current : $wb_current"
  vnote "target  : $wb_version (rev $wb_rev)"

  # Version gate: refuse to downgrade so a stale API response cannot roll
  # back a manual bump.
  skip_wb=false
  if [[ "$wb_version" != "$wb_current" ]]; then
    older=$(printf '%s\n%s\n' "$wb_version" "$wb_current" | sort -V | head -1)
    if [[ "$older" == "$wb_version" ]]; then
      pkg_skip "workbuddy" "API version $wb_version older than local $wb_current"
      skip_wb=true
    fi
  fi

  if [[ "$skip_wb" == true ]]; then
    :
  elif [[ "$wb_version" == "$wb_current" ]]; then
    pkg_up "workbuddy" "$wb_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "workbuddy" "$wb_current → $wb_version"
  else
    pkg_bump "workbuddy" "$wb_current → $wb_version"
    note "prefetching (~430 MB deb) ..."
    wb_hash=$(prefetch_hash "$wb_url")
    update_nix_field "$wb_nix" "version" "$wb_version"
    update_nix_field "$wb_nix" "rev" "$wb_rev"
    update_nix_field "$wb_nix" "hash" "$wb_hash"
  fi
fi

# ── cc-switch ────────────────────────────────────────────────────────

if should_update "cc-switch"; then
  status_begin "cc-switch"
  if command -v gh &>/dev/null; then
    cc_version=$(gh api repos/farion1231/cc-switch/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      cc_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/farion1231/cc-switch/releases/latest" || true)
    else
      cc_json=$(curl -sf --max-time 10 "https://api.github.com/repos/farion1231/cc-switch/releases/latest" || true)
    fi
    if [[ -z "$cc_json" ]]; then
      die "Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
    fi
    if echo "$cc_json" | jq -e '.message' >/dev/null 2>&1; then
      die "GitHub API request failed: $(echo "$cc_json" | jq -r '.message')" \
        "Try again later, set GITHUB_TOKEN, or install gh CLI."
    fi
    cc_version=$(echo "$cc_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  cc_nix="$REPO_ROOT/pkgs/cc-switch.nix"
  cc_current=$(grep 'version = ' "$cc_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $cc_current"
  vnote "latest  : $cc_version"

  if [[ "$cc_version" == "$cc_current" ]]; then
    pkg_up "cc-switch" "$cc_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "cc-switch" "$cc_current → $cc_version"
  else
    pkg_bump "cc-switch" "$cc_current → $cc_version"
    x64_url="https://github.com/farion1231/cc-switch/releases/download/v${cc_version}/CC-Switch-v${cc_version}-Linux-x86_64.deb"
    arm64_url="https://github.com/farion1231/cc-switch/releases/download/v${cc_version}/CC-Switch-v${cc_version}-Linux-arm64.deb"

    note "prefetching x86_64 ..."
    x64_hash=$(prefetch_hash "$x64_url")
    note "prefetching aarch64 ..."
    arm64_hash=$(prefetch_hash "$arm64_url")

    update_nix_field "$cc_nix" "version" "$cc_version"

    # Update x86_64 hash (first occurrence after x86_64 URL)
    sed -i "/x86_64\.deb/{n;s|hash = \".*\"|hash = \"${x64_hash}\"|;}" "$cc_nix"
    # Update aarch64 hash (first occurrence after arm64 URL)
    sed -i "/arm64\.deb/{n;s|hash = \".*\"|hash = \"${arm64_hash}\"|;}" "$cc_nix"
  fi
fi

# ── magpie ───────────────────────────────────────────────────────────

if should_update "magpie"; then
  status_begin "magpie"
  # /latest by design (Captain's call, 2026-10-27): upstream re-edits old
  # releases, which can skew its timestamp-based pick behind the newest tag
  # for one release cycle (2026-10-27: it returned v0.1.1720 while
  # v0.1.1722 existed; we pinned 1722 manually). Self-heals at the next
  # publish. Beware: running this update before that next publish would
  # "update" the pin back to the skewed /latest pick.
  if command -v gh &>/dev/null; then
    mg_version=$(gh api repos/yetone/magpie-releases/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      mg_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/yetone/magpie-releases/releases/latest" || true)
    else
      mg_json=$(curl -sf --max-time 10 "https://api.github.com/repos/yetone/magpie-releases/releases/latest" || true)
    fi
    if [[ -z "$mg_json" ]]; then
      die "Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
    fi
    if echo "$mg_json" | jq -e '.message' >/dev/null 2>&1; then
      die "GitHub API request failed: $(echo "$mg_json" | jq -r '.message')" \
        "Try again later, set GITHUB_TOKEN, or install gh CLI."
    fi
    mg_version=$(echo "$mg_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  mg_nix="$REPO_ROOT/pkgs/magpie.nix"
  mg_current=$(grep 'version = ' "$mg_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $mg_current"
  vnote "latest  : $mg_version"

  if [[ "$mg_version" == "$mg_current" ]]; then
    pkg_up "magpie" "$mg_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "magpie" "$mg_current → $mg_version"
  else
    pkg_bump "magpie" "$mg_current → $mg_version"
    x64_url="https://github.com/yetone/magpie-releases/releases/download/v${mg_version}/magpie-linux-amd64"
    arm64_url="https://github.com/yetone/magpie-releases/releases/download/v${mg_version}/magpie-linux-arm64"

    note "prefetching x86_64 ..."
    x64_hash=$(prefetch_hash "$x64_url")
    note "prefetching aarch64 ..."
    arm64_hash=$(prefetch_hash "$arm64_url")

    update_nix_field "$mg_nix" "version" "$mg_version"

    # Update x86_64 hash (first occurrence after the amd64 URL)
    sed -i "/magpie-linux-amd64/{n;s|hash = \".*\"|hash = \"${x64_hash}\"|;}" "$mg_nix"
    # Update aarch64 hash (first occurrence after the arm64 URL)
    sed -i "/magpie-linux-arm64/{n;s|hash = \".*\"|hash = \"${arm64_hash}\"|;}" "$mg_nix"
  fi
fi

# ── siyuan ───────────────────────────────────────────────────────────

if should_update "siyuan"; then
  status_begin "siyuan"
  if command -v gh &>/dev/null; then
    siyuan_version=$(gh api repos/siyuan-note/siyuan/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      siyuan_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/siyuan-note/siyuan/releases/latest" || true)
    else
      siyuan_json=$(curl -sf --max-time 10 "https://api.github.com/repos/siyuan-note/siyuan/releases/latest" || true)
    fi
    if [[ -z "$siyuan_json" ]]; then
      die "Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
    fi
    if echo "$siyuan_json" | jq -e '.message' >/dev/null 2>&1; then
      die "GitHub API request failed: $(echo "$siyuan_json" | jq -r '.message')" \
        "Try again later, set GITHUB_TOKEN, or install gh CLI."
    fi
    siyuan_version=$(echo "$siyuan_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  siyuan_nix="$REPO_ROOT/pkgs/siyuan.nix"
  siyuan_current=$(grep 'version = ' "$siyuan_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $siyuan_current"
  vnote "latest  : $siyuan_version"

  if [[ "$siyuan_version" == "$siyuan_current" ]]; then
    pkg_up "siyuan" "$siyuan_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "siyuan" "$siyuan_current → $siyuan_version"
  else
    pkg_bump "siyuan" "$siyuan_current → $siyuan_version"
    sums_url="https://github.com/siyuan-note/siyuan/releases/download/v${siyuan_version}/SHA256SUMS.txt"
    x64_asset="siyuan-${siyuan_version}-linux.deb"
    arm64_asset="siyuan-${siyuan_version}-linux-arm64.deb"

    note "fetching SHA256SUMS.txt ..."
    sums=$(curl -sfL --max-time 10 "$sums_url")
    if [[ -z "$sums" ]]; then
      die "Failed to fetch $sums_url"
    fi

    x64_raw=$(echo "$sums" | awk -v f="$x64_asset" '$2==f || $2=="*"f {print $1}')
    arm64_raw=$(echo "$sums" | awk -v f="$arm64_asset" '$2==f || $2=="*"f {print $1}')

    if [[ -z "$x64_raw" || -z "$arm64_raw" ]]; then
      die "Could not find hashes for $x64_asset / $arm64_asset in SHA256SUMS.txt"
    fi

    x64_hash=$(nix hash to-sri --extra-experimental-features nix-command "sha256:$x64_raw" 2>/dev/null | tail -1)
    arm64_hash=$(nix hash to-sri --extra-experimental-features nix-command "sha256:$arm64_raw" 2>/dev/null | tail -1)

    note "prefetching source tree (fetchFromGitHub v${siyuan_version}) ..."
    src_hash=$(nix --extra-experimental-features 'nix-command flakes' flake prefetch --json "github:siyuan-note/siyuan/v${siyuan_version}" 2>/dev/null | jq -r '.hash')
    if [[ -z "$src_hash" || "$src_hash" == "null" ]]; then
      die "nix flake prefetch failed for github:siyuan-note/siyuan/v${siyuan_version}"
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
    note "probing vendorHash (this triggers one build attempt that is expected to fail) ..."
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
      note "probe attempt ${probe_attempt}/${probe_max_attempts} produced no hash; retrying ..."
      probe_attempt=$((probe_attempt + 1))
      sleep 5
    done
    if [[ -z "$vendor_hash" ]]; then
      diag=("vendorHash probe failed. Last 20 lines of probe output follow.")
      if echo "$vendor_probe_output" | grep -q "doesn't match anything"; then
        diag+=("A modPostBuild substituteInPlace anchor no longer matches upstream")
        diag+=("(most likely the gulu 0644 patch in pkgs/siyuan.nix).")
        diag+=("Update the patch anchor for the new version, then re-run.")
      elif echo "$vendor_probe_output" | grep -q "called on an empty list"; then
        diag+=("No Linux host in this flake installs siyuan via home-manager,")
        diag+=("so there is nowhere to probe from.")
      fi
      die "${diag[@]}" "$(echo "$vendor_probe_output" | tail -20)"
    fi
    sed -i "s|vendorHash = \".*\"|vendorHash = \"${vendor_hash}\"|" "$siyuan_nix"
  fi
fi

# ── ww-manager ───────────────────────────────────────────────────────

if should_update "ww-manager"; then
  status_begin "ww-manager"
  ww_json=$(curl -sf --max-time 10 "https://pypi.org/pypi/ww-manager/json" || true)
  if [[ -z "$ww_json" ]]; then
    die "Failed to reach PyPI JSON API for ww-manager."
  fi
  ww_version=$(echo "$ww_json" | jq -r '.info.version')
  if [[ -z "$ww_version" || "$ww_version" == "null" ]]; then
    die "could not extract .info.version from PyPI response."
  fi

  ww_nix="$REPO_ROOT/pkgs/ww-manager.nix"
  ww_current=$(grep 'version = ' "$ww_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $ww_current"
  vnote "latest  : $ww_version"

  if [[ "$ww_version" == "$ww_current" ]]; then
    pkg_up "ww-manager" "$ww_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "ww-manager" "$ww_current → $ww_version"
  else
    pkg_bump "ww-manager" "$ww_current → $ww_version"
    ww_url="https://pypi.io/packages/source/w/ww-manager/ww_manager-${ww_version}.tar.gz"
    ww_hash=$(prefetch_hash "$ww_url")
    update_nix_field "$ww_nix" "version" "$ww_version"
    update_nix_field "$ww_nix" "hash" "$ww_hash"
  fi
fi

# ── notion-electron ─────────────────────────────────────────────────

if should_update "notion-electron"; then
  status_begin "notion-electron"
  if command -v gh &>/dev/null; then
    ne_version=$(gh api repos/anechunaev/notion-electron/releases/latest --jq '.tag_name' | sed 's/^v//')
  else
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      ne_json=$(curl -sf --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/anechunaev/notion-electron/releases/latest" || true)
    else
      ne_json=$(curl -sf --max-time 10 "https://api.github.com/repos/anechunaev/notion-electron/releases/latest" || true)
    fi
    if [[ -z "$ne_json" ]]; then
      die "Failed to reach GitHub API. Check your network or set GITHUB_TOKEN."
    fi
    if echo "$ne_json" | jq -e '.message' >/dev/null 2>&1; then
      die "GitHub API request failed: $(echo "$ne_json" | jq -r '.message')" \
        "Try again later, set GITHUB_TOKEN, or install gh CLI."
    fi
    ne_version=$(echo "$ne_json" | jq -r '.tag_name' | sed 's/^v//')
  fi

  ne_nix="$REPO_ROOT/pkgs/notion-electron.nix"
  ne_current=$(grep 'version = ' "$ne_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $ne_current"
  vnote "latest  : $ne_version"

  if [[ "$ne_version" == "$ne_current" ]]; then
    pkg_up "notion-electron" "$ne_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "notion-electron" "$ne_current → $ne_version"
  else
    pkg_bump "notion-electron" "$ne_current → $ne_version"
    ne_url="https://github.com/anechunaev/notion-electron/releases/download/v${ne_version}/Notion_Electron-${ne_version}-x86_64.AppImage"

    note "prefetching ..."
    ne_hash=$(prefetch_hash "$ne_url")

    update_nix_field "$ne_nix" "version" "$ne_version"
    update_nix_field "$ne_nix" "hash" "$ne_hash"
  fi
fi

# ── zcode-cli ────────────────────────────────────────────────────────

if should_update "zcode-cli"; then
  status_begin "zcode-cli"
  # GitHub releases lag the git tags here (latest release 3.14.3 vs tag
  # v3.15.1), so resolve the highest tag instead of the releases API.
  zc_version=$(
    git ls-remote --tags --refs https://github.com/zai-org/ZCode 'v*' \
      | awk -F/ '{print $3}' | sed 's/^v//' | sort -V | tail -1)
  if [[ -z "$zc_version" ]]; then
    die "git ls-remote found no tags for zai-org/ZCode."
  fi

  zc_nix="$REPO_ROOT/pkgs/zcode-cli.nix"
  zc_current=$(grep 'version = ' "$zc_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $zc_current"
  vnote "latest  : $zc_version"

  if [[ "$zc_version" == "$zc_current" ]]; then
    pkg_up "zcode-cli" "$zc_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "zcode-cli" "$zc_current → $zc_version"
  else
    pkg_bump "zcode-cli" "$zc_current → $zc_version"
    zc_url="https://github.com/zai-org/ZCode/archive/refs/tags/v${zc_version}.tar.gz"

    note "prefetching source ..."
    zc_hash=$(prefetch_hash "$zc_url")

    update_nix_field "$zc_nix" "version" "$zc_version"
    # Two hash lines exist (src + pnpmDeps); anchor each on its preceding
    # line instead of update_nix_field, which would hit both.
    sed -i "/archive\/refs\/tags/{n;s|hash = \".*\"|hash = \"${zc_hash}\"|;}" "$zc_nix"

    note "resolving pnpm store hash (downloads the whole lockfile store) ..."
    # The pnpmDeps hash cannot be prefetched: point it at a sentinel and
    # read the got-hash from the failed FOD build.
    sed -i '/fetcherVersion = 4;/{n;s|hash = ".*"|hash = lib.fakeHash|;}' "$zc_nix"
    zc_deps_hash=$(
      nix build --no-link --impure --expr \
        "(((builtins.getFlake \"$REPO_ROOT\").inputs.nixpkgs.legacyPackages.x86_64-linux).extend (import $REPO_ROOT/pkgs/default.nix)).zcode-cli.pnpmDeps" 2>&1 \
        | grep -oP 'got:\s+\Ksha256-[^=]+=' | head -1)
    if [[ -z "$zc_deps_hash" ]]; then
      die "could not resolve pnpmDeps hash; pkgs/zcode-cli.nix left at version $zc_version with a fakeHash sentinel."
    fi
    sed -i "/fetcherVersion = 4;/{n;s|hash = lib.fakeHash|hash = \"${zc_deps_hash}\"|;}" "$zc_nix"

    vnote "src ${zc_hash:0:14}... deps ${zc_deps_hash:0:14}..."
    note "run nix build on the package once to verify the full build."
  fi
fi

# ── dsh-tui-launcher ─────────────────────────────────────────────────

if should_update "dsh-tui-launcher"; then
  status_begin "dsh-tui-launcher"
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
    die "deepseek-harness missing from flake.lock (run: nix flake lock)."
  fi
  dt_kernel=$(nix --extra-experimental-features 'nix-command flakes' eval \
    --raw "github:moraxyc/deepseek-harness.nix/${dt_lock_rev}#packages.x86_64-linux.dsh.version" 2>/dev/null) || true
  if [[ -z "$dt_kernel" ]]; then
    die "could not resolve the kernel version from the locked deepseek-harness rev ${dt_lock_rev:0:7}."
  fi

  # The full packument is off-limits here: npm serves it with unescaped
  # control characters in the readme, which jq refuses to parse (and the
  # cache makes that intermittent). Version list comes from `npm view`,
  # and each candidate's contract from its clean per-version document.
  dt_versions=$(npm view @deepseek-harness-tui/dsh-tui versions --json 2>/dev/null \
    | jq -r 'if type == "array" then .[] else . end' 2>/dev/null)
  if [[ -z "$dt_versions" ]]; then
    die "could not list dsh-tui versions from the npm registry."
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
    die "no dsh-tui release accepts the pinned kernel $dt_kernel (npm latest: $dt_latest)." \
      "Update the deepseek-harness flake input to a kernel the newer" \
      "launchers accept, then re-run this updater."
  fi

  vnote "kernel  : $dt_kernel (from flake.lock)"
  vnote "current : $dt_current"
  vnote "target  : $dt_target (newest release accepting this kernel)"

  if [[ "$dt_target" == "$dt_current" ]]; then
    pkg_up "dsh-tui-launcher" "$dt_current"
  else
    older=$(printf '%s\n%s\n' "$dt_target" "$dt_current" | sort -V | head -1)
    if [[ "$older" == "$dt_target" ]]; then
      pkg_skip "dsh-tui-launcher" "newest compatible ($dt_target) is older than local ($dt_current)"
    elif [[ "$DRY_RUN" == true ]]; then
      pkg_dry "dsh-tui-launcher" "$dt_current → $dt_target"
    else
      pkg_bump "dsh-tui-launcher" "$dt_current → $dt_target"
      dt_url="https://registry.npmjs.org/@deepseek-harness-tui/dsh-tui/-/dsh-tui-${dt_target}.tgz"

      note "prefetching launcher tarball ..."
      dt_hash=$(prefetch_hash "$dt_url")

      update_nix_field "$dt_nix" "version" "$dt_target"
      update_nix_field "$dt_nix" "hash" "$dt_hash"
    fi
  fi

  # ── dsh-tui profile alignment (self-guarded) ─────────────────────────
  # The rolling TUI profile lives outside nix and does not follow kernel
  # bumps: its @deepseek-ai/* plugins pin the bootstrap-time kernel and
  # its dsh-tui copy advances only via the TUI's own /update. A kernel
  # family bump strands it, and the launcher's gate — hard-refuses when
  # the profile's TUI copy is older at major.minor (bin/dsh-tui.js
  # checkProfileAlignment) — then locks the only self-repair path; the
  # 2026-10-28 rc.2→rc.3 deadlock is exactly that shape. `dsh plugin
  # add` gates its peer contract against the RUNNING kernel, so
  # realignment only succeeds once the system generation is already on
  # dt_kernel (i.e. after nhs). Guard accordingly: while the running
  # kernel lags the lock, print the commands and touch nothing; on match,
  # realign in place. A profile TUI NEWER than the pin is soft-allowed by
  # the gate and must not be downgraded. Third-party profile plugins are
  # user-state by decision — reported, never touched. The Electron-managed
  # desktop profile is only compared (its single @deepseek-ai/* dep vs
  # the kernel) and pointed at its own repair path. All mutation is
  # failure-isolated so a pnpm/network error cannot abort the later
  # sections, and package.json/pnpm-lock.yaml are backed up next to
  # themselves (.pre-align, one rolling copy) before any change.
  dt_profile="$HOME/.dsh/profiles/dsh-tui"
  dt_tui_ver=$(jq -r '.version // empty' \
    "$dt_profile/node_modules/@deepseek-harness-tui/dsh-tui/package.json" 2>/dev/null) || true
  if [[ -n "$dt_tui_ver" ]]; then
    dt_run_kernel=$(dsh --version 2>/dev/null | head -1) || true
    dt_family_skew=$(jq -r --arg k "$dt_kernel" \
      '.dependencies | to_entries[]
       | select(.key | startswith("@deepseek-ai/dsh-"))
       | select(.value != $k) | .key + " " + .value' \
      "$dt_profile/package.json" 2>/dev/null) || true
    # Mirror the launcher's own gate: compare major.minor with any
    # prerelease suffix stripped.
    dt_tui_mm="${dt_tui_ver%%-*}"
    dt_tui_mm="${dt_tui_mm%.*}"
    dt_tgt_mm="${dt_target%%-*}"
    dt_tgt_mm="${dt_tgt_mm%.*}"
    dt_tui_older=false
    if [[ "$dt_tui_mm" != "$dt_tgt_mm" ]]; then
      if [[ "$(printf '%s\n%s\n' "$dt_tui_mm" "$dt_tgt_mm" | sort -V | head -1)" \
        == "$dt_tui_mm" ]]; then
        dt_tui_older=true
      fi
    fi
    dt_add_args=()
    if [[ "$dt_tui_older" == true ]]; then
      dt_add_args+=("@deepseek-harness-tui/dsh-tui@$dt_target")
    fi
    if [[ -n "$dt_family_skew" ]]; then
      while IFS= read -r dt_dep; do
        if [[ -n "$dt_dep" ]]; then
          dt_add_args+=("${dt_dep%% *}@$dt_kernel")
        fi
      done <<< "$dt_family_skew"
    fi
    if [[ -z "${dt_add_args[*]}" ]]; then
      vnote "profile: aligned (tui $dt_tui_ver, family $dt_kernel)"
    elif [[ "$dt_run_kernel" != "$dt_kernel" ]]; then
      note "dsh-tui profile behind (tui $dt_tui_ver) and running kernel ${dt_run_kernel:-missing} != target $dt_kernel — after switching, run:"
      note "  dsh plugin --profile dsh-tui add ${dt_add_args[*]}"
    elif [[ "$DRY_RUN" == true ]]; then
      note "[dry-run] would realign dsh-tui profile: dsh plugin --profile dsh-tui add ${dt_add_args[*]}"
    else
      note "realigning dsh-tui profile (tui $dt_tui_ver, family skew) to kernel $dt_kernel ..."
      cp "$dt_profile/package.json" "$dt_profile/package.json.pre-align"
      cp "$dt_profile/pnpm-lock.yaml" "$dt_profile/pnpm-lock.yaml.pre-align" 2>/dev/null || true
      if timeout 300 dsh plugin --profile dsh-tui add "${dt_add_args[@]}" >/dev/null 2>&1; then
        dt_new_tui=$(jq -r '.dependencies["@deepseek-harness-tui/dsh-tui"] // "?"' \
          "$dt_profile/package.json" 2>/dev/null) || true
        note "dsh-tui profile realigned (tui now $dt_new_tui, family $dt_kernel)"
      else
        note "dsh-tui profile realignment FAILED — run manually to see the error:"
        note "  dsh plugin --profile dsh-tui add ${dt_add_args[*]}"
      fi
    fi
    if [[ "$VERBOSE" == true ]]; then
      dt_third=$(jq -r '[.dependencies | to_entries[]
                  | select((.key | startswith("@deepseek-ai/dsh-")) | not)
                  | select(.key != "@deepseek-harness-tui/dsh-tui")
                  | "\(.key) \(.value)"] | join("; ")' \
        "$dt_profile/package.json" 2>/dev/null) || true
      if [[ -n "$dt_third" ]]; then
        vnote "third-party profile plugins (untouched): $dt_third"
      fi
    fi
  else
    vnote "profile: not installed (the launcher bootstraps it on first run)"
  fi
  dt_desk_sub=$(jq -r '.dependencies["@deepseek-ai/dsh-subagent-codex"] // empty' \
    "$HOME/.dsh/profiles/desktop/package.json" 2>/dev/null) || true
  if [[ -n "$dt_desk_sub" && "$dt_desk_sub" != "$dt_kernel" ]]; then
    note "desktop profile pins dsh-subagent-codex $dt_desk_sub (kernel $dt_kernel) — realign via the desktop app's plugin manager"
  fi
fi

# ── ene-fanctl ───────────────────────────────────────────────────────
# Userspace driver for the ENE 6K7750 ARGB controller
# (pkgs/ene-fanctl.nix). Upstream is a one-shot repo: created 2026-10-01,
# one commit, zero stars/issues since — no releases exist, so this tracks
# the default-branch HEAD. Two local patches
# (pkgs/ene-fanctl-scale.patch, pkgs/ene-fanctl-no-park.patch) ride on
# the pinned rev and are re-applied at build time; if a build fails after
# a bump, refresh those two patches against the new source.

if should_update "ene-fanctl"; then
  status_begin "ene-fanctl"
  ef_nix="$REPO_ROOT/pkgs/ene-fanctl.nix"
  ef_current=$(grep -oP 'rev = "\K[0-9a-f]{40}' "$ef_nix" | head -1)
  ef_json=""
  ef_sha=""
  if command -v gh &>/dev/null; then
    ef_json=$(gh api repos/teamlocabit/ene-6k7750-rgb/commits/main 2>/dev/null) || true
    ef_sha=$(echo "${ef_json:-}" | jq -r '.sha // empty' 2>/dev/null)
  fi
  if [[ -z "$ef_sha" || "$ef_sha" == "null" ]]; then
    ef_auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && ef_auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    ef_json=$(curl -sf --max-time 10 "${ef_auth[@]}" \
      "https://api.github.com/repos/teamlocabit/ene-6k7750-rgb/commits/main") || true
    ef_sha=$(echo "${ef_json:-}" | jq -r '.sha // empty' 2>/dev/null)
  fi
  if [[ -z "$ef_sha" || "$ef_sha" == "null" ]]; then
    die "could not read the HEAD sha of teamlocabit/ene-6k7750-rgb."
  fi

  vnote "current : ${ef_current:0:7}"
  vnote "target  : ${ef_sha:0:7}"

  # Commit shas are unordered, so there is no downgrade gate here; the
  # equality check alone decides.
  if [[ "$ef_sha" == "$ef_current" ]]; then
    pkg_up "ene-fanctl" "${ef_current:0:7}"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "ene-fanctl" "${ef_current:0:7} → ${ef_sha:0:7}"
    note "if the next build fails, refresh pkgs/ene-fanctl-{scale,no-park}.patch against the new source."
  else
    pkg_bump "ene-fanctl" "${ef_current:0:7} → ${ef_sha:0:7}"
    ef_date=$(echo "$ef_json" | jq -r '.commit.committer.date // empty' 2>/dev/null | cut -d'T' -f1)
    # fetchFromGitHub's hash is the unpacked-tree narHash, NOT the raw
    # tarball hash that prefetch_hash computes — flake prefetch speaks the
    # same hash (verified: reproduces the pinned sha256 for the current rev).
    ef_hash=$(nix --extra-experimental-features 'nix-command flakes' flake prefetch --json \
      "github:teamlocabit/ene-6k7750-rgb/${ef_sha}" 2>/dev/null | jq -r '.hash // empty')
    if [[ -z "$ef_hash" ]]; then
      die "could not prefetch the source tree hash."
    fi
    update_nix_field "$ef_nix" "rev" "$ef_sha"
    update_nix_field "$ef_nix" "hash" "$ef_hash"
    [[ -n "$ef_date" ]] && update_nix_field "$ef_nix" "version" "0-unstable-${ef_date}"
    note "if the next build fails, refresh pkgs/ene-fanctl-{scale,no-park}.patch against the new source."
  fi
fi

# ── wechat ───────────────────────────────────────────────────────────

if should_update "wechat"; then
  status_begin "wechat"
  # Tencent ships no version API and keeps no history on the official CDN;
  # the mirror archive is also the URL pkgs/default.nix actually fetches,
  # so its latest release tag is the single source of truth here.
  wechat_version=$(github_latest_version "Rodert/wechat-linux-versions")

  wechat_nix="$REPO_ROOT/pkgs/default.nix"
  # Invariant: pkgs/default.nix pins exactly one version/hash pair (the
  # wechat overlay), so the global substitutions in update_nix_field and
  # the URL rewrite below touch only wechat's lines.
  wechat_current=$(grep 'version = ' "$wechat_nix" | head -1 | grep -oP '[\d.]+')

  vnote "current : $wechat_current"
  vnote "latest  : $wechat_version"

  if [[ "$wechat_version" == "$wechat_current" ]]; then
    pkg_up "wechat" "$wechat_current"
  elif [[ "$DRY_RUN" == true ]]; then
    pkg_dry "wechat" "$wechat_current → $wechat_version"
  else
    pkg_bump "wechat" "$wechat_current → $wechat_version"
    wechat_url="https://github.com/Rodert/wechat-linux-versions/releases/download/v${wechat_version}/WeChatLinux_x86_64.AppImage"

    note "prefetching (~300 MB AppImage) ..."
    wechat_hash=$(prefetch_hash "$wechat_url")

    update_nix_field "$wechat_nix" "version" "$wechat_version"
    update_nix_field "$wechat_nix" "hash" "$wechat_hash"
    # The download URL embeds the version separately from `version = `.
    sed -i "s|/download/v${wechat_current}/|/download/v${wechat_version}/|" "$wechat_nix"
  fi
fi

# ── qq (pinned nixpkgs input) ────────────────────────────────────────
# qq is pinned (overlay in modules/nixos/desktop/qq-wayland-fix.nix) to
# the nixpkgs rev that linuxqq-wayland-fix tests against, read from the
# fix's own flake.lock. This entry aligns the pin with the fix version
# already recorded in flake.lock; the linuxqq-wayland-fix input itself
# is never touched here (it rides the regular flake update).

if should_update "qq"; then
  status_begin "qq"
  flake_nix="$REPO_ROOT/flake.nix"
  flake_lock="$REPO_ROOT/flake.lock"

  # qq version shipped by an nixpkgs rev (x86_64-linux entry of sources.nix).
  qq_version_at() {
    curl -sf --max-time 30 "https://raw.githubusercontent.com/NixOS/nixpkgs/$1/pkgs/by-name/qq/qq/sources.nix" |
      awk '/x86_64-linux = \{/ { f = 1; next } f && /version = / { sub(/.*version = "/, ""); sub(/".*/, ""); print; exit }' || true
  }

  current_rev=$(grep -oP 'nixpkgs-qq\.url = "github:NixOS/nixpkgs/\K[0-9a-f]{40}' "$flake_nix" || true)
  if [[ -z "$current_rev" ]]; then
    die "could not read the nixpkgs-qq rev from flake.nix."
  fi

  fix_rev=$(jq -r '.nodes["linuxqq-wayland-fix"].locked.rev // empty' "$flake_lock")
  if [[ -z "$fix_rev" ]]; then
    die "linuxqq-wayland-fix is missing from flake.lock." \
      "Run: nix flake lock   (adds missing lock entries)"
  fi

  target_rev=$(curl -sf --max-time 30 "https://raw.githubusercontent.com/SHORiN-KiWATA/linuxqq-wayland-fix/${fix_rev}/flake.lock" |
    jq -r '.nodes.nixpkgs.locked.rev // empty' || true)
  if [[ -z "$target_rev" ]]; then
    die "could not read the nixpkgs rev from linuxqq-wayland-fix's flake.lock (fix rev ${fix_rev:0:7}). Upstream layout changed?"
  fi

  qq_current=$(qq_version_at "$current_rev")
  qq_target=$(qq_version_at "$target_rev")
  if [[ -z "$qq_current" || -z "$qq_target" ]]; then
    die "could not read qq versions from nixpkgs sources.nix" \
      "(pin ${current_rev:0:7}, target ${target_rev:0:7})."
  fi

  vnote "current : $qq_current @ ${current_rev:0:7}"
  vnote "target  : $qq_target @ ${target_rev:0:7}"

  # Version gate: follow the fix's qq version, and refuse to downgrade so
  # a lagging upstream pin cannot roll back a manual bump.
  skip_qq=false
  if [[ "$qq_target" == "$qq_current" ]]; then
    pkg_up "qq" "$qq_current"
  else
    older=$(printf '%s\n%s\n' "$qq_target" "$qq_current" | sort -V | head -1)
    if [[ "$older" == "$qq_target" ]]; then
      pkg_skip "qq" "fix currently pins qq $qq_target, older than local $qq_current"
      skip_qq=true
    fi
  fi

  if [[ "$skip_qq" == true ]]; then
    :
  elif [[ "$qq_target" != "$qq_current" && "$DRY_RUN" == false ]]; then
    pkg_bump "qq" "$qq_current → $qq_target"
    note "repinning nixpkgs-qq (${current_rev:0:7} → ${target_rev:0:7}) ..."
    sed -i "s|nixpkgs-qq.url = \"github:NixOS/nixpkgs/${current_rev}\"|nixpkgs-qq.url = \"github:NixOS/nixpkgs/${target_rev}\"|" "$flake_nix"
    # Positional input form: `flake lock --update-input` is deprecated.
    # The pin URL targets a fixed rev, so "update" re-resolves to exactly
    # that rev — no risk of picking up a newer nixpkgs.
    nix --extra-experimental-features 'nix-command flakes' flake update --flake "$REPO_ROOT" nixpkgs-qq
  elif [[ "$qq_target" != "$qq_current" ]]; then
    pkg_dry "qq" "$qq_current → $qq_target"
  fi
fi

# ── summary ──────────────────────────────────────────────────────────

parts=()
if [[ $n_updated -gt 0 ]]; then parts+=("$n_updated updated"); fi
if [[ $n_dry -gt 0 ]]; then parts+=("$n_dry would update"); fi
if [[ $n_skipped -gt 0 ]]; then parts+=("$n_skipped skipped"); fi
if [[ $n_uptodate -gt 0 ]]; then parts+=("$n_uptodate up to date"); fi
tally=""
for p in "${parts[@]}"; do
  tally+="${tally:+ · }$p"
done
if [[ -z "$tally" ]]; then
  tally="nothing selected (--only matched no package)"
fi
printf '\n%s (%ss)\n' "$tally" "$SECONDS"
