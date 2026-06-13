#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OPT_PROJECT=""
OPT_WORKSPACE=""
workspace_dirs=()
while [ $# -gt 0 ]; do
    case "$1" in
        -p) OPT_PROJECT="$2"; shift 2 ;;
        -w) OPT_WORKSPACE="$2"; shift 2 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) workspace_dirs+=("$1"); shift ;;
    esac
done

calc_container_name

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: container ${CONTAINER_NAME} already exists" >&2
    exit 1
fi

select_env
echo "Using config: $(basename "$SELECTED_ENV")"

load_env "$SELECTED_ENV"
check_required

mkdir -p "$STORAGE_DIR/config"

mount_list=("${STORAGE_DIR}/config -> /home/coder/.config")
volume_args="-v ${STORAGE_DIR}/config:/home/coder/.config"
for dir in "${workspace_dirs[@]+${workspace_dirs[@]}}"; do
    if [ ! -d "$dir" ]; then
        echo "Warning: directory not found, skipping: $dir" >&2
        continue
    fi
    dir=$(realpath "$dir")
    name=$(basename "$dir")
    volume_args="$volume_args -v ${dir}:/home/coder/projects/${name}"
    mount_list+=("${dir} -> /home/coder/projects/${name}")
done

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${PORT:-34567}:9080" \
    -e TZ="${TZ:-Asia/Shanghai}" \
    -e PASSWORD="$PASSWORD" \
    -u "$(id -u):$(id -g)" \
    --restart unless-stopped \
    $volume_args \
    "$IMAGE" \
    "${OPT_WORKSPACE:-/home/coder/projects}"

echo ""
echo "----------------------------------------------------------"
echo "code-server-plus started"
echo "  Container : ${CONTAINER_NAME}"
echo "  URL       : http://localhost:${PORT:-34567}/<YYYYMMDDHHMM>"
echo "  Password  : ${PASSWORD}"
echo "  Workspace : ${OPT_WORKSPACE:-/home/coder/projects}"
echo "  Mounts    :"
for m in "${mount_list[@]}"; do
    echo "    ${m}"
done
echo "----------------------------------------------------------"
