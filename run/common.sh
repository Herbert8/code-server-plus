#!/usr/bin/env bash

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVS_DIR="$RUN_DIR/envs"
STORAGE_DIR="$RUN_DIR/storage"

select_env() {
    local env_files=("$ENVS_DIR"/*.env)
    if [ ${#env_files[@]} -eq 0 ] || [ ! -f "${env_files[0]}" ]; then
        echo "Error: no env files found ($ENVS_DIR/*.env)" >&2
        exit 1
    fi

    echo "Select environment:"
    for i in "${!env_files[@]}"; do
        echo "  $((i+1))) $(basename "${env_files[$i]}" .env)"
    done

    read -rp "Enter number [1]: " choice
    choice=${choice:-1}

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#env_files[@]} ]; then
        echo "Error: invalid selection" >&2
        exit 1
    fi

    SELECTED_ENV="${env_files[$((choice - 1))]}"
}

load_env() {
    local env_file="$1"
    if [ ! -f "$env_file" ]; then
        echo "Error: env file not found: $env_file" >&2
        exit 1
    fi
    set -a
    source "$env_file"
    set +a
}

check_required() {
    if [ -z "${PASSWORD:-}" ]; then
        echo "Error: PASSWORD not set, please configure in env file" >&2
        exit 1
    fi
    if [ -z "${TOTP_SECRET:-}" ]; then
        echo "Error: TOTP_SECRET not set, please configure in env file" >&2
        exit 1
    fi
    if [ -z "${JWT_SECRET:-}" ]; then
        echo "Error: JWT_SECRET not set, please configure in env file" >&2
        exit 1
    fi
    if [ -z "${IMAGE:-}" ]; then
        echo "Error: IMAGE not set, please configure in env file" >&2
        exit 1
    fi
}

calc_container_name() {
    if [ -n "${OPT_PROJECT:-}" ]; then
        CONTAINER_NAME="csp-${OPT_PROJECT}"
    else
        CONTAINER_NAME="csp-$(echo -n "$RUN_DIR" | cksum | cut -d' ' -f1)"
    fi
}

select_container() {
    local OPT_PROJECT=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -p) OPT_PROJECT="$2"; shift 2 ;;
            -*) echo "Unknown option: $1" >&2; exit 1 ;;
            *) shift ;;
        esac
    done

    if [ -n "$OPT_PROJECT" ]; then
        echo "csp-${OPT_PROJECT}"
        return
    fi

    local containers
    containers=$(docker ps -a --filter "name=csp-" --format '{{.Names}}')
    if [ -z "$containers" ]; then
        echo "Error: no csp-* containers found" >&2
        exit 1
    fi

    local arr=($containers)
    if [ ${#arr[@]} -eq 1 ]; then
        echo "${arr[0]}"
        return
    fi

    echo "Select container:"
    local i=1
    for c in "${arr[@]}"; do
        local status
        status=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "unknown")
        echo "  $i) $c ($status)"
        ((i++))
    done

    read -rp "Enter number [1]: " choice
    choice=${choice:-1}

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#arr[@]} ]; then
        echo "Error: invalid selection" >&2
        exit 1
    fi

    echo "${arr[$((choice - 1))]}"
}
