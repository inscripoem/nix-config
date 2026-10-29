# Show available commands.
default:
    @{{quote(just_executable())}} --list

# Update custom package versions (optional package, --dry-run, --verbose).
update *args:
    #!/usr/bin/env bash
    set -euo pipefail
    flags=()
    pkgs=()
    for a in {{args}}; do
        case "$a" in
            --dry|--dry-run) flags+=(--dry-run) ;;
            --verbose|-v) flags+=(--verbose) ;;
            --only=*) flags+=("$a") ;;
            -*) echo "update: unknown flag: $a" >&2; exit 2 ;;
            *) pkgs+=("$a") ;;
        esac
    done
    if [[ ${#pkgs[@]} -gt 1 ]]; then
        echo "update: at most one package name (use --only=a,b for several)" >&2
        exit 2
    fi
    pkg="${pkgs[0]:-}"

    if [[ -z "$pkg" ]]; then
        exec ./scripts/update-versions.sh "${flags[@]}"
    else
        exec ./scripts/update-versions.sh "${flags[@]}" --only="$pkg"
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
# `just lint` chains lint-modules (pure shell, no nix), the QML gate
# and deadnix. The nix-run tools come from this flake's locked nixpkgs
# input via `--inputs-from .`; no extra flake input, no devShell.
# `lint-qml` runs qmllint with FULL DMS type resolution. qmllint
# ships inside qt6.qtdeclarative but is not its mainProgram, hence
# the explicit store-path lookup. The dux-shell source (the exact
# tree the installed binary builds from, locked by flake.lock) is
# staged as a writable copy because quickshell resolves `qs.*` as
# directory imports at runtime while qmllint needs explicit qmldir
# manifests; one qmldir per directory is synthesized (`module qs.X`
# header, every .qml as a component, `pragma Singleton` files as
# singletons) — the same mapping quickshell applies implicitly.
# Strictness, tuned around empirically-verified qmllint 6.12 behavior:
# syntax/structural errors exit non-zero on their own; missing-property
# findings and qs.* import failures only print, so both are escalated to
# fatal by explicit output scans below. Do NOT use `-W 0` here: combined
# with a disabled category it exits 255 without printing the findings.
# `--unqualified disable` silences cross-scope id references
# (Component/delegate bodies reaching outer ids) — default QML behavior
# and the ecosystem-wide style. Known residual gap: qmllint only proves
# member absence on narrow receiver shapes (parent chains to concrete
# Item types); member typos reached via ids or qmldir-declared
# singletons (Theme.xyz) go undetected, and qmlplugindump cannot dump
# pure-QML modules that need the quickshell runtime — no stronger QML
# analyzer exists (qmllint/qmlls is the whole ecosystem). Runtime
# behavior still needs a DMS plugin reload to confirm.
# Generated hardware files retain upstream boilerplate. The scan path
# precedes `--exclude` because deadnix consumes all following values.
# `just check` evaluates every NixOS and Darwin host, or one named host.
# `just dry-run <host>` previews build requirements without activation.
# ══════════════════════════════════════════════════════════════
# Syntax-check all DMS plugin QML files with full DMS type resolution.
lint-qml:
    #!/usr/bin/env bash
    set -euo pipefail
    qt=$(nix build --no-warn-dirty --no-link --print-out-paths \
        --inputs-from . 'nixpkgs#qt6.qtdeclarative')
    qsh=$(nix build --no-warn-dirty --no-link --print-out-paths \
        --inputs-from . 'nixpkgs#quickshell')
    dms=$(nix build --no-warn-dirty --no-link --print-out-paths \
        --inputs-from . 'nixpkgs#dux-shell.src')
    stage=$(mktemp -d)
    trap 'rm -rf "$stage"' EXIT
    cp -rL "$dms/quickshell" "$stage/qs"
    chmod -R u+w "$stage/qs"
    shopt -s nullglob
    for dir in $(find "$stage/qs" -type d); do
        entries="module qs$(printf '%s' "${dir#"$stage/qs"}" | sed 's|/|.|g')"
        for f in "$dir"/*.qml; do
            base=$(basename "$f" .qml)
            if grep -q "pragma Singleton" "$f"; then
                entries+=$'\n'"singleton $base 1.0 $base.qml"
            else
                entries+=$'\n'"$base 1.0 $base.qml"
            fi
        done
        printf '%s\n' "$entries" > "$dir/qmldir"
    done
    files=(modules/nixos/desktop/dms-plugins/*/*.qml)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "no QML files under modules/nixos/desktop/dms-plugins" >&2
        exit 2
    fi
    rc=0
    out=$("$qt/bin/qmllint" \
        -I "$qt/lib/qt-6/qml" -I "$qsh/lib/qt-6/qml" -I "$stage" \
        --unqualified disable \
        "${files[@]}" 2>&1) || rc=$?
    [[ -z "$out" ]] || printf '%s\n' "$out"
    if [[ $rc -ne 0 ]]; then
        exit "$rc"
    fi
    if grep -q '\[missing-property\]' <<<"$out"; then
        echo "lint-qml: FAIL (member-level findings above)" >&2
        exit 1
    fi
    if grep -q 'Failed to import qs\.' <<<"$out"; then
        echo "lint-qml: FAIL (qs.* imports unresolved — dux-shell staging drifted)" >&2
        exit 1
    fi

# Static reachability check for the manual registration chain: every
# .nix in a manifest directory must be reachable from its default.nix,
# and every class directory must be claimed by a host or reserved.
# Pure text inspection — no nix. RESERVED whitelist: script header.
lint-modules:
    ./scripts/check-module-registration.sh

# Check module registration, unused Nix declarations, then the QML gate above.
lint: lint-modules lint-qml
    nix run --no-warn-dirty --inputs-from . 'nixpkgs#deadnix' -- \
        --fail \
        . \
        --exclude \
        hosts/briefcase/hardware-configuration.nix \
        hosts/vm/hardware-configuration.nix

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
#     just install-remote <host> <ip>
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
