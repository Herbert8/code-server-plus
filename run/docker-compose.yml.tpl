services:
  code-server:
    image: ${IMAGE:?请在 env 文件中设置 IMAGE}
    user: "${USER_ID:?请通过 start.sh 启动}:${GROUP_ID:?请通过 start.sh 启动}"
    ports:
      - "${PORT:-34567}:8080"
    environment:
      - TZ=${TZ:-Asia/Shanghai}
      - PASSWORD=${PASSWORD:?请在 env 文件中设置 PASSWORD}
    volumes:
      - ${VOLUME_NAME:?请在 env 文件中设置 VOLUME_NAME}:/home/coder
      {{WORKSPACE_VOLUMES}}
    restart: unless-stopped
