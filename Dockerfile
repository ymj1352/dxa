#FROM node:20-alpine3.20
FROM alpine:3.20

WORKDIR /tmp

# 只复制启动脚本
COPY start.sh ./

EXPOSE 8080

# 只安装必要的运行时依赖
RUN apk update && apk add --no-cache openssl curl tar gcompat bash && \
    chmod +x start.sh && \
    # 清理缓存
    rm -rf /var/cache/apk/*

# x-tunnel-img.playingapi.tech
CMD ["./start.sh"]
