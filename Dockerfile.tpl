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
EXPOSE 8080
