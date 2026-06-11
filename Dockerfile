FROM alpine:3.20

# 创建一个专用的应用目录，并确保所有用户都有读写权限（应对无 root 容器平台）
WORKDIR /app

# 复制启动脚本
COPY start.sh ./

# 安装运行时依赖（包含用于静态网页的 python3）
RUN apk update && apk add --no-cache openssl openssh wget tar bash ca-certificates gcompat libc6-compat python3 && \
    chmod +x /app/start.sh && \
    rm -rf /var/cache/apk/*

# 同时暴露 80 和 8080 端口
EXPOSE 80
EXPOSE 8080

# 推荐使用绝对路径执行
CMD [ "/app/start.sh" ]
