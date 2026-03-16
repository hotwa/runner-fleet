#!/bin/bash
# Runner Fleet 初始化脚本
# 用于首次部署或系统重启后确保目录权限正确

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 容器运行用户 UID (默认 1001)
RUNNER_UID=${RUNNER_UID:-1001}
RUNNER_GID=${RUNNER_GID:-1001}

echo "=== Runner Fleet 初始化 ==="
echo "项目目录: $PROJECT_DIR"
echo "Runner UID/GID: $RUNNER_UID:$RUNNER_GID"

# 确保 runners 目录存在并设置正确权限
if [ ! -d "$PROJECT_DIR/runners" ]; then
    echo "创建 runners 目录..."
    mkdir -p "$PROJECT_DIR/runners"
fi

# 设置目录权限
echo "设置目录权限..."
sudo chown -R $RUNNER_UID:$RUNNER_GID "$PROJECT_DIR/config" 2>/dev/null || true
sudo chown -R $RUNNER_UID:$RUNNER_GID "$PROJECT_DIR/runners" 2>/dev/null || true

# 确保 runner-net 网络存在
echo "检查 runner-net 网络..."
docker network inspect runner-net >/dev/null 2>&1 || docker network create runner-net

# 检查现有 runner 容器并修复权限
echo "检查现有 runner 目录权限..."
for runner_dir in "$PROJECT_DIR/runners"/*/; do
    if [ -d "$runner_dir" ]; then
        runner_name=$(basename "$runner_dir")
        echo "  - 修复 $runner_name 权限"
        sudo chown -R $RUNNER_UID:$RUNNER_GID "$runner_dir" 2>/dev/null || true
    fi
done

echo "=== 初始化完成 ==="
