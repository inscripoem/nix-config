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
