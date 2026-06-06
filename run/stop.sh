#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

container=$(select_container "$@")
docker stop "$container" && docker rm "$container"
echo "已停止并删除容器：${container}"
