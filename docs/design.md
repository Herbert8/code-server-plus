# code-server-plus 设计文档

## 1. 架构概览

```
浏览器 ──→ OpenResty (9080) ──→ code-server (8080)
              │
              ├─ access_by_lua: TOTP 校验 / Cookie 检查
              └─ proxy_pass: 反向代理 + WebSocket 升级
```

- **OpenResty** 监听 9080 端口，作为前置网关
- **code-server** 监听 8080 端口，不对外暴露
- 容器对外只暴露 9080 端口（`EXPOSE 9080`）

### ENTRYPOINTD 启动机制

利用 code-server 基础镜像的 `/entrypoint.d/*.sh` 机制，在容器启动时自动运行 OpenResty：

```bash
# /entrypoint.d/10-openresty.sh
#!/bin/sh
openresty
```

OpenResty 在 code-server 之前启动，作为后台守护进程运行。

## 2. OpenResty 选型与集成

### 为什么选 OpenResty 而非 nginx

普通 nginx 不支持 Lua，无法在请求阶段做动态校验。OpenResty 内置 LuaJIT，可以直接在 `access_by_lua_block` 中执行 TOTP 计算、Cookie 管理等逻辑。

### 基础镜像选择

| 镜像 | OpenResty 支持 | 选择 |
|------|---------------|------|
| Debian 13 (Trixie) | ❌ 无 Trixie 仓库 |  |
| Ubuntu 24.04 (Noble) | ✅ 官方仓库 | ✅ |

基础镜像从 Debian 切换到 Ubuntu，唯一原因就是 OpenResty 官方提供了 Noble 的 apt 仓库。

### conf.d 注入方式

OpenResty 默认的 `nginx.conf` **不包含** `include /etc/openresty/conf.d/*.conf`，需要通过 `sed` 在 Docker 构建时注入：

```dockerfile
RUN sed -i '/http {/a\    include /etc/openresty/conf.d/*.conf;' \
    /usr/local/openresty/nginx/conf/nginx.conf
```

## 3. WebSocket 代理

### $host vs $http_host

这是调试中最坑的问题之一。code-server 有一个 `authenticateOrigin` 安全检查：它会解析浏览器发来的 `Origin` 头中的 host（含端口），然后与转发过来的 `Host` 头做精确字符串比较。

```
┌──────────────────────────────────────────────────────────────────┐
│ 问题场景                                                         │
│                                                                  │
│ 浏览器 Origin: http://localhost:34567 → 解析出 "localhost:34567" │
│                                                                  │
│ 使用 $host 转发:    Host: localhost（丢失端口）                  │
│ 比较: "localhost" ≠ "localhost:34567" → WebSocket 被拒绝 (1006) │
│                                                                  │
│ 使用 $http_host 转发: Host: localhost:34567（保留端口）          │
│ 比较: "localhost:34567" = "localhost:34567" → 通过               │
└──────────────────────────────────────────────────────────────────┘
```

- `$host`：nginx 内部变量，按优先级取 Host 头的域名部分（不含端口）
- `$http_host`：原始 Host 头的完整值（含端口）

**必须用 `$http_host`。**

### proxy_read_timeout

WebSocket 连接是长连接，nginx 默认 `proxy_read_timeout` 是 60 秒。如果没有数据传输，连接会被断开。设置为 `3600s` 确保长时间空闲的 WebSocket 连接不会被杀掉。

## 4. TOTP 动态校验

### 为什么 TOTP 而非时间 token

之前实现过一个基于 `os.date("%Y%m%d%H%M")` 的时间 token 方案，存在时区问题：

| 方案 | 时区依赖 | 安全性 | 体验 |
|------|---------|--------|------|
| 时间 token (`/YYYYMMDDHHMM`) | ❌ 依赖容器 TZ | 低（可预测） | 需记住当前时间 |
| TOTP (RFC 6238) | ✅ 使用 Unix 时间戳，与时区无关 | 高（需密钥） | Authenticator APP 生成 |

TOTP 使用 Unix 时间戳（`ngx.time()` / `os.time()`），与时区完全无关，且需要密钥才能生成，安全性更高。

### TOTP 原理（RFC 6238）

```
1. 取当前 Unix 时间戳，除以 30 得到时间窗口计数器 T
2. HMAC-SHA1(密钥, T 的 8 字节大端表示) → 20 字节哈希
3. 取哈希最后一字节的低 4 位作为偏移量 offset
4. 从哈希的 offset 位置取 4 字节，去掉最高位（& 0x7FFFFFFF）
5. 对 1000000 取模，左补零到 6 位 → TOTP 码
```

验证时允许 ±1 时间窗口（前后各 30 秒），共 90 秒容差。

### 库选型对比

| 方案 | 优点 | 缺点 | 选择 |
|------|------|------|------|
| DIY 实现 | 无依赖 | Base32 解码有 bug，需自己维护 | ❌ |
| lua-resty-otp (leslie-tsang) | `calc_token(var_time)` 接受时间参数，支持 ±1 窗口；有测试；Apache-2.0 | 9 stars，小众 | ✅ |
| otp (alues) | API 类似，15 stars | `calc_token()` **不接受时间参数**，无法实现 ±1 窗口；有全局变量泄漏；无 LICENSE | ❌ |

**关键差异**：alues/otp 的 `calc_token()` 内部直接用 `ngx.time()`，不接受参数。这意味着无法传入 `now±30` 来做容差检查，除非修改库源码。

lua-resty-otp 的 `calc_token(var_time)` 接受时间戳参数，正好满足 ±1 窗口需求。

该库零外部依赖，仅使用 OpenResty 内置的 `ngx.hmac_sha1` 和 `bit` 运算，单文件 205 行，直接 vendor 到 `build/resty/otp.lua`。

### Base32 密钥规则

TOTP 密钥是 **Base32 编码**（RFC 4648）。

**硬性规则：**
- 字符集：`A-Z` 和 `2-7`（Base32 字母表，无小写、无 `0/1/8/9`）
- 库会自动处理大小写转换和 `=` padding 去除
- 只要字符在合法范围内，随便写即可

**不需要管的：**
- 解码后是什么内容（就是一串随机字节，本来也应该是随机的）
- 是否是 8 的倍数长度（非整数倍只是末尾几位 bit 被忽略）
- 是否有 `=` padding

**长度建议：**

| 长度 | 位数 | 说明 |
|------|------|------|
| 16 字符 | 80 bits | 最低可用（Google Authenticator 要求） |
| 26 字符 | 130 bits | RFC 4226 最低要求 |
| 32 字符 | 160 bits | RFC 4226 推荐，生产环境建议 |

当前测试密钥 `JBSWY3DPEHPK3PXP`（16 字符）可以工作，生产环境建议使用 32 字符。

**生成方式：**

```bash
# 推荐：用工具生成随机密钥
openssl rand -base32 20

# 手敲也行，只要字符在 A-Z 和 2-7 范围内
# 例如：ABCDE234567QRSTUVWXYZ234567
```

### ±1 窗口容差

用户输入 TOTP 码时可能刚好在窗口切换的边界（例如 29 秒时生成，提交时已进入下一窗口）。±1 窗口检查允许验证通过前一个、当前、后一个窗口的码，共 90 秒容差。

```lua
local now = ngx.time()
for _, off in ipairs({0, -1, 1}) do
    if code == totp:calc_token(now + off * 30) then
        -- 验证通过
    end
end
```

### Cookie 机制

TOTP 验证通过后，设置 Cookie 实现后续请求免验证：

```
auth_token=1; Path=/; HttpOnly; Max-Age=10800
```

| 属性 | 值 | 说明 |
|------|-----|------|
| Name | `auth_token` | Cookie 名称 |
| Value | `1` | 占位值（code-server 有自己的密码认证） |
| HttpOnly | 是 | 防止 XSS 读取 |
| Max-Age | 10800 (3 小时) | 过期后需重新输入 TOTP |
| Path | / | 全局有效 |

### 访问流程

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 用户打开 Authenticator APP，获取 6 位 TOTP 码（如 956603）   │
│                                                                 │
│ 2. 浏览器访问 http://localhost:34567/956603                     │
│    OpenResty access_by_lua:                                      │
│      ├─ 匹配 URL /(\d{6})                                        │
│      ├─ 计算 TOTP，检查 ±1 窗口                                  │
│      ├─ 匹配 → Set-Cookie: auth_token=1                          │
│      └─ 302 重定向到 /                                           │
│                                                                 │
│ 3. 浏览器跟随重定向，带上 Cookie 访问 /                          │
│    OpenResty access_by_lua:                                      │
│      ├─ 无 6 位码匹配                                            │
│      ├─ 检查 cookie_auth_token → 存在                            │
│      └─ 放行，proxy_pass → code-server (8080)                   │
│                                                                 │
│ 4. code-server 返回登录页，用户输入密码进入编辑器                │
│                                                                 │
│ 5. 后续请求都带 Cookie，直接通过 OpenResty 到达 code-server     │
│    Cookie 3 小时后过期，需重新输入 TOTP 码                       │
└─────────────────────────────────────────────────────────────────┘
```

## 5. build.py 职责分离

`generate` 和 `build` 两个子命令分离：

| 命令 | 职责 | 何时使用 |
|------|------|---------|
| `generate` | 从 `tools.toml` + `Dockerfile.tpl` 生成 `Dockerfile` 和 `README.md` | `tools.toml` 或 `Dockerfile.tpl` 有变更时 |
| `build` | 只执行 `docker build` | `Dockerfile` 已存在，构建镜像 |

`build` 不会自动调用 `generate`，Dockerfile 不存在时报错提示先运行 `generate`。

这样分离的好处：
- 调试 `nginx.conf` 等配置文件时反复 `build` 不会重新查 GitHub API
- 避免 `generate` 覆盖对 Dockerfile 的临时修改

## 6. 待办 / 后续

- [ ] TOTP 密钥改为环境变量传参（当前写死 `JBSWY3DPEHPK3PXP`）
- [ ] `start.sh` 启动时显示 QR 码（集成 `qrencode`）
- [ ] 推送镜像到 Docker Hub
