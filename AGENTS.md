# Runner Fleet 部署指南

本项目是 GitHub Actions Self-hosted Runner 管理服务，支持容器化部署每个 Runner 实例。

## 项目结构

```
├── Dockerfile              # Manager 镜像
├── Dockerfile.runner       # Runner Agent 镜像
├── docker-compose.yml      # Docker Compose 配置
├── config.yaml.example     # 配置示例
├── .env.example           # 环境变量示例
├── cmd/                   # 源代码
├── internal/
└── scripts/
    ├── init.sh            # 初始化脚本
    └── runner-fleet.service  # systemd 服务文件
```

## 前置要求

- Docker 20.10+
- Docker Compose v2+
- 宿主机 docker 组 GID（用于容器访问 Docker socket）
- 可访问 GitHub 的网络（或配置代理）

## 快速部署

### 1. 克隆仓库

```bash
git clone https://github.com/hotwa/runner-fleet.git
cd runner-fleet
```

### 2. 创建配置文件

```bash
# 创建目录
mkdir -p config runners

# 复制配置示例
cp config.yaml.example config/config.yaml

# 复制环境变量示例
cp .env.example .env
```

### 3. 配置环境变量 (重要)

编辑 `.env` 文件：

```bash
# Manager 镜像（本地构建用 runner-fleet-manager:local）
MANAGER_IMAGE=runner-fleet-manager:local

# Runner 镜像（本地构建用 runner-fleet-runner:local）
RUNNER_IMAGE=runner-fleet-runner:local

# 容器模式（每个 Runner 独立容器）
CONTAINER_MODE=true
CONTAINER_NETWORK=runner-net
JOB_DOCKER_BACKEND=none

# Docker 配置
DOCKER_HOST=unix:///var/run/docker.sock
DOCKER_GID=<宿主机 docker 组 GID>  # 运行: getent group docker | cut -d: -f3

# Basic Auth（管理界面认证）
BASIC_AUTH_USER=<用户名>
BASIC_AUTH_PASSWORD=<密码>

# 代理配置（如需要）
HTTP_PROXY=http://<代理地址>:<端口>
HTTPS_PROXY=http://<代理地址>:<端口>
NO_PROXY=localhost,127.0.0.1
```

### 4. 构建 Docker 镜像

```bash
# 如果网络需要代理访问 Go 模块，设置 GOPROXY
docker build --network=host -t runner-fleet-manager:local -f Dockerfile \
  --build-arg GOPROXY="https://goproxy.cn|direct" .

docker build --network=host -t runner-fleet-runner:local -f Dockerfile.runner \
  --build-arg GOPROXY="https://goproxy.cn|direct" .
```

**注意：** 如果使用代理构建，添加以下参数：
```bash
--build-arg HTTP_PROXY=http://127.0.0.1:11888 \
--build-arg HTTPS_PROXY=http://127.0.0.1:11888
```

### 5. 创建 Docker 网络

```bash
docker network create runner-net
```

### 6. 设置目录权限

```bash
# Manager 以 UID 1001 运行
sudo chown -R 1001:1001 config runners
```

### 7. 启动服务

```bash
docker compose up -d
```

### 8. 访问管理界面

打开浏览器访问 `http://<服务器IP>:8080`，使用 Basic Auth 登录。

## 添加 Runner

1. 在管理界面点击「添加 Runner」
2. 填写：
   - **Name**: Runner 名称
   - **Target Type**: `repo` 或 `org`
   - **Target**: 仓库或组织名（如 `owner/repo`）
   - **Labels**: 标签（可选）
   - **Registration Token**: 从 GitHub Settings → Actions → Runners 获取
3. 提交后等待后台自动安装和注册

## 配置开机自启

```bash
# 复制 systemd 服务文件
sudo cp scripts/runner-fleet.service /etc/systemd/system/

# 修改服务文件中的 PROJECT_DIR 路径
sudo sed -i "s|/home/zly/runner-fleet|$(pwd)|" /etc/systemd/system/runner-fleet.service

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable runner-fleet
```

## 常见问题

### 1. Runner 状态显示 unknown / EOF 错误

**原因：** Manager 容器设置了代理，内部容器通信被代理拦截。

**解决：** 已在代码中修复（使用 `noProxyClient`），确保使用最新构建的镜像。

### 2. Go 模块下载超时

**解决：** 使用国内 Go 代理构建：
```bash
--build-arg GOPROXY="https://goproxy.cn|direct"
```

### 3. Docker CLI 安装失败

**解决：** 国内网络使用阿里云镜像（已在 Dockerfile 中配置）。

### 4. 权限错误

**解决：**
```bash
sudo chown -R 1001:1001 config runners
```

### 5. Docker socket 权限错误

**解决：** 确保 `DOCKER_GID` 与宿主机 docker 组 GID 一致：
```bash
getent group docker | cut -d: -f3
```

## 代理配置说明

### Runner 容器代理（Job 流量走代理）

在 `.env` 中配置：
```bash
HTTP_PROXY=http://host.docker.internal:11888
HTTPS_PROXY=http://host.docker.internal:11888
NO_PROXY=localhost,127.0.0.1
```

这些代理设置会传递到 Runner 容器，供 Job 中的网络请求使用。

### Manager 与 Agent 内部通信

**已内置处理：** Manager 使用 `noProxyClient` 与 Runner Agent 通信，不会受代理影响。

## 镜像说明

| 镜像 | 用途 | 大小 |
|------|------|------|
| `runner-fleet-manager:local` | Manager 服务，管理 Runner | ~200MB |
| `runner-fleet-runner:local` | Runner Agent，执行 Job | ~512MB |

## 相关文件

- `internal/config/config.go`: 配置定义
- `internal/runner/container.go`: 容器管理与 Agent 通信
- `internal/handler/handler.go`: HTTP API 处理
- `scripts/init.sh`: 初始化脚本
- `scripts/runner-fleet.service`: systemd 服务
