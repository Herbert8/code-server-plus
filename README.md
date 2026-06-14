# code-server-plus

基于 [codercom/code-server](https://hub.docker.com/r/codercom/code-server) 的增强开发环境镜像，集成 OpenResty 网关认证和常用开发工具。

## 功能特性

- **TOTP 动态码认证**：通过 Authenticator APP 生成 6 位验证码访问，无需暴露原始密码
- **JWT 会话管理**：验证通过后签发 HS256 JWT Cookie（3 小时有效期），签名+过期双重校验
- **OpenResty 反向代理**：前置网关处理认证，WebSocket 代理支持在线编辑器
- **安全隐蔽**：伪装 Server 头为 nginx，自定义 404 页面，避免指纹识别
- **开发工具齐全**：集成 50+ 命令行工具，涵盖搜索、文件管理、网络调试、数据库客户端等

## 配置

启动前需在 `run/envs/default.env` 中填写三个必填项：

```bash
IMAGE=tecpoirot/code-server-plus:latest
PORT=34567
TZ=Asia/Shanghai
PASSWORD=                    # code-server 登录密码
TOTP_SECRET=                 # TOTP 密钥（Base32，A-Z 和 2-7）
JWT_SECRET=                  # JWT 签名密钥（任意随机字符串）
```

生成密钥：

```bash
# TOTP_SECRET（Base32，添加到 Authenticator APP）
openssl rand -base32 20

# JWT_SECRET
openssl rand -hex 32
```

## 使用方法

### 构建镜像

```bash
# 生成 Dockerfile 和 README
python3 build/build.py generate

# 构建镜像
python3 build/build.py build
```

### 启动容器

```bash
# 启动（交互选择环境配置，需先配置 default.env）
./run/start.sh

# 停止
./run/stop.sh

# 重启
./run/restart.sh

# 查看日志
./run/logs.sh

# 查看状态
./run/status.sh
```

## 访问方式

1. 在 Authenticator APP 中添加 `TOTP_SECRET` 对应的密钥
2. 浏览器访问 `http://localhost:<PORT>/<6位TOTP码>`
3. 验证通过后自动跳转到 code-server 登录页，输入 `PASSWORD` 即可进入编辑器
4. 3 小时内无需重新输入 TOTP 码

## 工具清单

<!-- TOOLS_TABLE_START -->
### 包管理器安装

| 名称 | 说明 |
|------|------|
| ripgrep | 极速文本搜索工具 |
| fd-find | find 的快速替代品（二进制名为 fdfind，已创建 fd 符号链接） |
| bat | cat 的增强替代品，支持语法高亮（二进制名为 batcat，已创建 bat 符号链接） |
| fzf | 命令行模糊查找器 |
| tmux | 终端复用器 |
| htop | 交互式进程查看器 |
| ncdu | 交互式磁盘用量分析器 |
| p7zip-full | 高压缩比压缩/解压工具 |
| unzip | ZIP 解压工具 |
| redis-tools | Redis 客户端工具 |
| default-mysql-client | MySQL 客户端工具 |
| postgresql-client | PostgreSQL 客户端工具 |
| ncat | NMAP netcat 实现，支持 SSL/代理等高级功能 |
| netcat-openbsd | 网络调试工具 |
| dropbear-bin | 轻量级 SSH 服务器/客户端 |
| bzip2 | bzip2 压缩/解压工具 |
| zstd | Zstandard 高性能压缩/解压工具 |
| jq | 命令行 JSON 处理工具 |
| lnav | 终端日志查看和分析工具 |
| iputils-ping | ping 网络诊断工具 |
| iproute2 | ip、ss 等网络配置工具 |
| dnsutils | dig、nslookup 等 DNS 查询工具 |
| traceroute | 网络路由追踪工具 |
| net-tools | ifconfig、netstat、route 等传统网络工具 |

### 二进制下载

| 名称 | 说明 |
|------|------|
| eza | ls 的现代替代品，支持颜色和图标 |
| lazygit | 终端 Git UI 工具 |
| croc | 安全快速的文件传输工具 |
| duf | 磁盘使用情况查看工具 |
| hexyl | 终端十六进制查看器 |
| yq | 命令行 YAML/JSON/XML 处理器 |
| xh | 友好且快速的 HTTP 客户端 |
| zoxide | 智能 cd 命令替代品 |
| yazi | 终端文件管理器 |
| aichat | 终端 AI 聊天客户端，支持多种 LLM |
| opencode | 终端 AI 编码助手，支持多种 LLM |
| usql | 通用数据库客户端，内置多种数据库驱动 |
| bun | 高性能 JavaScript 运行时和包管理器 |
| uv | 高性能 Python 包管理器，可自动管理 Python 版本 |
| ttyd | 在浏览器中共享终端的工具 |
| git-flow | git-flow AVH 的 Rust 重写版，高性能 Git 分支管理工作流 |
| delta | 语法高亮的 git diff 查看器 |
| fx | 终端 JSON 交互式查看器 |
| glow | 终端 Markdown 渲染器 |
| zellij | 现代终端复用器 |
| starship | 跨 shell 的提示符美化工具 |
| dust | du 的现代替代品，可视化磁盘使用 |
| procs | ps 的现代替代品 |
| btop | htop 的现代替代品，系统资源监控 |
| tailspin | 带语法高亮的日志查看器 |
| websocat | WebSocket 命令行调试工具 |
| filebrowser | Web 文件管理器，支持上传/下载/分享 |

### 扩展安装

| 名称 | 说明 |
|------|------|
| ahmadawais.shades-of-purple | Shades of Purple 主题 |

<!-- TOOLS_TABLE -->
