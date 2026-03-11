#FROM node:20-alpine3.20
FROM alpine:3.20

WORKDIR /tmp

COPY start.sh ./

#EXPOSE 53
#EXPOSE 10000  # dns-proxy Web界面
EXPOSE 3000  # x-tunnel 端口
#EXPOSE 30001  # usque 端口

# 只安装必要的运行时依赖
RUN apk update && apk add --no-cache openssl curl tar gcompat bash && \
    chmod +x start.sh && \
    # 清理缓存
    rm -rf /var/cache/apk/*

CMD ["./start.sh"]
