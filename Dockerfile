FROM alpine:3.20

# 创建一个专用的应用目录，并确保所有用户都有读写权限（应对无 root 容器平台）
WORKDIR /app

# 复制启动脚本
COPY start.sh ./

# 只安装必要的运行时依赖，并确保脚本可执行
RUN apk update && apk add --no-cache openssl openssh wget tar bash ca-certificates gcompat libc6-compat && \
    chmod +x /app/start.sh && \
    rm -rf /var/cache/apk/*

# 暴露端口
EXPOSE 8080

# 推荐使用绝对路径执行
CMD ["/app/start.sh"]
