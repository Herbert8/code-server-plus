#!/usr/bin/env bash
# compose.sh - 共享代码，被其他脚本 source

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_TPL="$RUN_DIR/docker-compose.yml.tpl"
COMPOSE_FILE="$RUN_DIR/docker-compose.yml"
ENVS_DIR="$RUN_DIR/envs"

compose_cmd() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo "错误：未找到 docker-compose.yml，请先运行 start.sh" >&2
        exit 1
    fi
    docker compose -f "$COMPOSE_FILE" "$@"
}

list_envs() {
    local env_files=("$ENVS_DIR"/*.env)
    if [ ${#env_files[@]} -eq 0 ] || [ ! -f "${env_files[0]}" ]; then
        echo "错误：未找到 env 文件（$ENVS_DIR/*.env）" >&2
        exit 1
    fi

    echo "请选择环境配置："
    local i=1
    for f in "${env_files[@]}"; do
        local name
        name=$(basename "$f" .env)
        echo "  $i) $name"
        ((i++))
    done

    read -rp "请输入编号 [1]: " choice
    choice=${choice:-1}

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#env_files[@]} ]; then
        echo "错误：无效的选择" >&2
        exit 1
    fi

    SELECTED_ENV="${env_files[$((choice - 1))]}"
}

load_env() {
    local env_file="$1"
    if [ ! -f "$env_file" ]; then
        echo "错误：env 文件不存在：$env_file" >&2
        exit 1
    fi
    set -a
    source "$env_file"
    set +a
}

check_password() {
    if [ -z "${PASSWORD:-}" ]; then
        echo "错误：PASSWORD 未设置，请在 env 文件中配置" >&2
        exit 1
    fi
}

generate_compose() {
    local workspace_volumes="$1"

    local content
    content=$(cat "$COMPOSE_TPL")

    content="${content//\{\{WORKSPACE_VOLUMES\}\}/$workspace_volumes}"

    echo "$content" > "$COMPOSE_FILE"
}
