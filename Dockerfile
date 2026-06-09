#FROM node:20-alpine3.20
FROM alpine:3.20

WORKDIR /tmp

COPY start.sh ./

EXPOSE 8080

# 只安装必要的运行时依赖
RUN apk update && apk add --no-cache openssl openssh wget tar gcompat bash && \
    chmod +x start.sh && \
    # 清理缓存
    rm -rf /var/cache/apk/*

CMD ["./start.sh"]
