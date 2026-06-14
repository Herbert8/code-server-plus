# 第一阶段：从其他镜像提取二进制
{{STAGE_FROM_BLOCKS}}
# 最终阶段
FROM {{BASE_IMAGE}}

USER root

# 通过包管理器安装工具
RUN apt-get update && apt-get install -y --no-install-recommends {{PACKAGE_LIST}} \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# 安装 OpenResty
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget gnupg ca-certificates \
    && wget -qO - https://openresty.org/package/pubkey.gpg \
       | gpg --dearmor -o /usr/share/keyrings/openresty.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/openresty.gpg] https://openresty.org/package/ubuntu noble main" \
       > /etc/apt/sources.list.d/openresty.list \
    && apt-get update && apt-get install -y --no-install-recommends openresty openresty-opm \
    && rm -rf /var/lib/apt/lists/*
# 安装 lua-resty-jwt（JWT 签发与验证）
RUN opm get SkyLothar/lua-resty-jwt
COPY nginx.conf /etc/openresty/conf.d/code-server.conf
COPY resty/otp.lua /usr/local/openresty/lualib/resty/otp.lua
RUN rm -f /etc/openresty/conf.d/default.conf \
    && sed -i -e '/^events {/i\env TOTP_SECRET;\nenv JWT_SECRET;\n' \
              -e '/http {/a\    include /etc/openresty/conf.d/*.conf;' \
       /usr/local/openresty/nginx/conf/nginx.conf \
    && chown -R coder:coder /usr/local/openresty/nginx

# 从其他镜像复制二进制
{{STAGE_COPY_BLOCKS}}
# 下载第三方二进制
{{BINARY_DOWNLOADS}}
# 配置 shell 别名
RUN cat >> /etc/bash.bashrc << 'ALIASES'
export EZA_COLORS="da=32:uu=0:gu=0"
alias llz='eza -ghlF --git --git-repos --time-style="+%F %T" --group-directories-first --color-scale --color=auto'
alias llg='ls -lp --time-style="+%F %T" --group-directories-first --color=auto'
alias ll=llz
ALIASES

# 安装 code-server 扩展
USER coder
{{EXTENSION_INSTALLS}}
# 清理构建时生成的缓存和配置
RUN rm -rf ~/.config/code-server \
    && rm -rf ~/.local/share/code-server/CachedExtensionVSIXs \
              ~/.local/share/code-server/CachedProfilesData \
              ~/.local/share/code-server/logs \
              ~/.local/share/code-server/coder-logs \
              ~/.local/share/code-server/Machine \
              ~/.local/share/code-server/User \
              ~/.local/share/code-server/machineid

USER root

# OpenResty 启动脚本（通过 ENTRYPOINTD 机制自动执行）
RUN mkdir -p /entrypoint.d \
    && cat > /entrypoint.d/10-openresty.sh << 'SCRIPT'
#!/bin/sh
openresty
SCRIPT
RUN chmod +x /entrypoint.d/10-openresty.sh

EXPOSE 9080
