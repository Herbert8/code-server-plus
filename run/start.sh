#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/compose.sh"

list_envs
env_file="$SELECTED_ENV"
echo "使用配置：$(basename "$env_file")"

load_env "$env_file"
check_password

read -rp "请输入要挂载的目录（空格分隔，回车跳过）: " workspace_input

workspace_volumes=""
if [ -n "$workspace_input" ]; then
    for dir in $workspace_input; do
        if [ ! -d "$dir" ]; then
            echo "警告：目录不存在，跳过：$dir" >&2
            continue
        fi
        dir=$(realpath "$dir")
        name=$(basename "$dir")
        workspace_volumes="${workspace_volumes}
      - ${dir}:/home/coder/projects/${name}"
    done
fi

export USER_ID=$(id -u)
export GROUP_ID=$(id -g)

generate_compose "$workspace_volumes"

compose_cmd up -d

echo ""
echo "┌─────────────────────────────────────────┐"
echo "│ code-server-plus 已启动                  │"
echo "├─────────────────────────────────────────┤"
echo "│ 地址：http://localhost:${PORT:-34567}"
echo "│ 密码：${PASSWORD}"
echo "└─────────────────────────────────────────┘"
