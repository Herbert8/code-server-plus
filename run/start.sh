#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OPT_PROJECT=""
workspace_dirs=()
while [ $# -gt 0 ]; do
    case "$1" in
        -p) OPT_PROJECT="$2"; shift 2 ;;
        -*) echo "未知选项：$1" >&2; exit 1 ;;
        *) workspace_dirs+=("$1"); shift ;;
    esac
done

calc_container_name

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "错误：容器 ${CONTAINER_NAME} 已存在" >&2
    exit 1
fi

select_env
echo "使用配置：$(basename "$SELECTED_ENV")"

load_env "$SELECTED_ENV"
check_required

mkdir -p "$STORAGE_DIR/config"

volume_args="-v ${STORAGE_DIR/config}:/home/coder/.config"
for dir in "${workspace_dirs[@]+${workspace_dirs[@]}}"; do
    if [ ! -d "$dir" ]; then
        echo "警告：目录不存在，跳过：$dir" >&2
        continue
    fi
    dir=$(realpath "$dir")
    name=$(basename "$dir")
    volume_args="$volume_args -v ${dir}:/home/coder/projects/${name}"
done

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${PORT:-34567}:8080" \
    -e TZ="${TZ:-Asia/Shanghai}" \
    -e PASSWORD="$PASSWORD" \
    -u "$(id -u):$(id -g)" \
    --restart unless-stopped \
    $volume_args \
    "$IMAGE"

echo ""
echo "┌──────────────────────────────────────────┐"
echo "│ code-server-plus 已启动                   │"
echo "├──────────────────────────────────────────┤"
echo "│ 容器：${CONTAINER_NAME}"
echo "│ 地址：http://localhost:${PORT:-34567}"
echo "│ 密码：${PASSWORD}"
echo "└──────────────────────────────────────────┘"
