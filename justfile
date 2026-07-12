default: update

update *args:
    #!/usr/bin/env bash
    set -euo pipefail
    dry=""
    filtered=()
    for a in {{args}}; do
        case "$a" in
            --dry|--dry-run) dry="--dry-run" ;;
            *) filtered+=("$a") ;;
        esac
    done
    pkg="${filtered[0]:-}"
    version="${filtered[1]:-}"

    if [[ -z "$pkg" ]]; then
        ./scripts/update-versions.sh $dry
    elif [[ "$pkg" == "trae-cn" && -n "$version" ]]; then
        ./scripts/update-versions.sh --only=trae-cn --trae-version="$version" $dry
    else
        ./scripts/update-versions.sh --only="$pkg" $dry
    fi

apply target="":
    #!/usr/bin/env bash
    set -euo pipefail
    colmena_rc=0

    if [[ -z "{{target}}" ]]; then
        colmena apply || colmena_rc=$?
    else
        colmena apply --on '{{target}}' || colmena_rc=$?
    fi

    # Workaround NixOS bug #74899: switch-to-configuration does not
    # reliably restart socket-activated services (avahi). Runs even
    # when colmena fails.
    if [[ -n "{{target}}" ]]; then
        ssh -o ConnectTimeout=8 "root@{{target}}.local" \
            'systemctl is-active avahi-daemon -q || systemctl restart avahi-daemon.socket avahi-daemon.service' 2>/dev/null || :
    fi
    # IP fallback for hosts where mDNS is down.
    case "{{target}}" in
        wyse3040)
            ssh -o ConnectTimeout=8 "root@192.168.0.162" \
                'systemctl is-active avahi-daemon -q || systemctl restart avahi-daemon.socket avahi-daemon.service' 2>/dev/null || :
            ;;
    esac

    exit $colmena_rc

# ══════════════════════════════════════════════════════════════
# Verification — AGENTS.md §1 hard rule.
# `just check` iterates every host in .#nixosConfigurations and
# forces evaluation of its top-level derivation path.
# ══════════════════════════════════════════════════════════════
check host="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{host}}" ]]; then
        for h in $(nix eval --json --no-warn-dirty '.#nixosConfigurations' --apply 'builtins.attrNames' | jq -r '.[]'); do
            echo "▶ $h"
            nix eval --no-warn-dirty ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" > /dev/null
        done
    else
        nix eval --no-warn-dirty ".#nixosConfigurations.{{host}}.config.system.build.toplevel.drvPath"
    fi

# ══════════════════════════════════════════════════════════════
# Initial install (bare host or Live USB). Runs on briefcase;
# the target only receives the closure. Reboots after install.
#
#     just install-remote wyse3040 192.168.0.162
#
# See docs/wyse3040-install.md §5.
# ══════════════════════════════════════════════════════════════
install-remote host ip *extra:
    nix run 'github:nix-community/nixos-anywhere' -- \
        --flake '.#{{host}}' \
        --generate-hardware-config nixos-generate-config 'hosts/{{host}}/hardware-configuration.nix' \
        {{extra}} \
        root@'{{ip}}'
