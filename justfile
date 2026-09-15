# Show available commands.
default:
    @{{quote(just_executable())}} --list

# Update custom package versions (optional package, trae-cn version, --dry-run).
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

# Deploy NixOS hosts via Colmena (optional host or selector).
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

    exit $colmena_rc

# ══════════════════════════════════════════════════════════════
# Verification — AGENTS.md §1 hard rule.
# `just lint` checks for unused Nix declarations with the deadnix
# package from this flake's locked nixpkgs input.
# Generated hardware files retain upstream boilerplate. The scan path
# precedes `--exclude` because deadnix consumes all following values.
# `just check` evaluates every NixOS and Darwin host, or one named host.
# `just dry-run <host>` previews build requirements without activation.
# ══════════════════════════════════════════════════════════════
# Check unused Nix declarations using the locked nixpkgs input.
lint:
    nix run --no-warn-dirty --inputs-from . 'nixpkgs#deadnix' -- \
        --fail \
        . \
        --exclude \
        hosts/briefcase/hardware-configuration.nix \
        hosts/vm/hardware-configuration.nix \
        hosts/wyse3040/hardware-configuration.nix

# Evaluate one host, or all NixOS and Darwin hosts when omitted.
check host="": (_verify "eval" host)

# Preview a host's build requirements without building or activating it.
dry-run host: (_verify "dry-run" host)

[positional-arguments]
_verify action host:
    #!/usr/bin/env bash
    set -euo pipefail
    action="$1"
    host="$2"
    targets=()
    for collection in nixosConfigurations darwinConfigurations; do
        # Keep discovery in an assignment: failures must not become an empty,
        # successful loop (including when nix or jq fails in the pipeline).
        hosts=$(nix eval --json --no-warn-dirty ".#$collection" --apply 'builtins.attrNames' | jq -r '.[]')
        while IFS= read -r h; do
            [[ -n "$h" ]] || continue
            if [[ -z "$host" || "$host" == "$h" ]]; then
                targets+=("$collection.$h")
            fi
        done <<< "$hosts"
    done
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "Unknown host: $host (see outputs/default.nix)" >&2
        exit 2
    fi
    for target in "${targets[@]}"; do
        echo "▶ $target"
        case "$action" in
            eval)
                nix eval --no-warn-dirty ".#$target.config.system.build.toplevel.drvPath"
                ;;
            dry-run)
                nix build --no-warn-dirty --no-link --dry-run ".#$target.config.system.build.toplevel"
                ;;
        esac
    done

# ══════════════════════════════════════════════════════════════
# Initial install (bare host or Live USB). Runs on briefcase;
# the target only receives the closure. Reboots after install.
#
#     just install-remote wyse3040 <wyse3040-ip>
#
# See docs/wyse3040-install.md §5.
# ══════════════════════════════════════════════════════════════
install-remote host ip *extra:
    nix run 'github:nix-community/nixos-anywhere' -- \
        --flake '.#{{host}}' \
        --generate-hardware-config nixos-generate-config 'hosts/{{host}}/hardware-configuration.nix' \
        {{extra}} \
        root@'{{ip}}'

# ══════════════════════════════════════════════════════════════
# Build a WSL-importable tarball for a `wsl.*` host. The output
# is written to ./result-<host>.wsl so it lands in a gitignored
# path (see .gitignore: `result-*`) rather than polluting the
# tree with a top-level nixos.wsl. Requires root because
# tarballBuilder performs a full nixos-install into a temp
# rootfs. Extra flags after the host name are forwarded to the
# builder, e.g.:
#
#     just build-tarball nutshell --extra-files ./extra --chown /home/inscripoem 1000:100
#
# Note: tarballBuilder rejects more than one positional argument,
# so avoid passing an output path in `{{extra}}` — this recipe
# always appends `./result-<host>.wsl` as the sole positional.
#
# See https://nix-community.github.io/NixOS-WSL/building.html
# ══════════════════════════════════════════════════════════════
build-tarball host="nutshell" *extra:
    #!/usr/bin/env bash
    set -euo pipefail
    attr=".#nixosConfigurations.{{host}}.config.system.build.tarballBuilder"
    out="./result-{{host}}.wsl"
    echo "▶ building $attr → $out"
    sudo nix run --no-warn-dirty "$attr" -- {{extra}} "$out"
    echo "✔ tarball written to $(readlink -f "$out")"
