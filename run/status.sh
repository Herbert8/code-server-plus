#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

containers=$(docker ps -a --filter "name=csp-" --format '{{.Names}}')
if [ -z "$containers" ]; then
    echo "No csp-* containers found"
    exit 0
fi

echo "Containers:"
docker ps -f name="csp-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
