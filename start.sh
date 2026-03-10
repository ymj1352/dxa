#!/bin/bash
set -e

# ==========================
# 下载地址声明
XRAY_URL="${XRAY_URL:-https://dufs.f.mfs.cc.cd/data/xray/xray.tar.gz}"
DNS_PROXY_URL="${DNS_PROXY_URL:-https://dufs.f.mfs.cc.cd/data/dns-proxy/dns-proxy.tar.gz}"
X_TUNNEL_URL="${X_TUNNEL_URL:-https://dufs.f.mfs.cc.cd/data/x-tunnel/x-tunnel.tar.gz}"
CLOUDFLARED_URL="${CLOUDFLARED_URL:-https://dufs.f.mfs.cc.cd/data/cloudflared/cloudflared.tar.gz}"
USQUE_URL="${USQUE_URL:-https://dufs.f.mfs.cc.cd/data/usque/usque.tar.gz}"

# ==========================
# 默认 MODE
# MODE 支持的模式及说明：
# server_direct   -> 直连服务器模式
# server_argo     -> argo服务器模式
# client_tunnel   -> dns-proxy + x-tunnel客户端模式运行
# client_xray     -> dns-proxy + xray客户端模式运行
# client_usque    -> dns-proxy + usque客户端模式运行
# x-tunnel        -> x-tunnel模式运行
# dns-proxy       -> dns-proxy模式运行
# usque           -> usque模式运行
MODE="${MODE:-client_tunnel}"

# ==========================
# usque 启动控制
# USQUE=true 时，除非在usque模式下，否则都启动usque模式
USQUE="${USQUE:-false}"

# ==========================
# 复制函数（优先级：/root > /app > 网络下载）
fetch_and_copy() {
    local name="$1"
    local url="$2"

    # 1. 首先检查/root目录（docker挂载文件夹）
    if [ -e "/root/$name" ]; then
        echo "使用 /root/$name ..."
    # 2. 然后检查/app目录（镜像内置）
    elif [ -f "/app/$name.tar.gz" ]; then
        echo "使用本地 /app/$name.tar.gz 并解压到 /root/$name ..."
        tar -xzf "/app/$name.tar.gz" -C "/root/"
    # 3. 最后从网络下载
    else
        echo "下载 $name 到 /root ..."
        cd /root
        curl -L -f --retry 3 "$url" -o "$name.tar.gz"
        tar -xzf "$name.tar.gz"
        rm -f "$name.tar.gz"
    fi

    # 验证/root/$name是否存在
    if [ ! -e "/root/$name" ]; then
        echo "错误: /root/$name 不存在或解压失败"
        exit 1
    fi

    # 4. 统一从/root目录复制到当前目录（/tmp）
    echo "从 /root/$name 复制到 $PWD/ ..."
    if [ -d "/root/$name" ]; then
        # 对于xray目录，特殊处理配置文件
        if [ "$name" == "xray" ]; then
            # 复制目录内容，排除config.json
            find "/root/$name" -type f -not -name "config.json" -exec cp -a {} "$PWD/" \;
            # 单独复制config.json并重命名为xray.json
            if [ -f "/root/$name/config.json" ]; then
                echo "复制 /root/xray/config.json 为 $PWD/xray.json ..."
                cp -a "/root/$name/config.json" "$PWD/xray.json"
            fi
        else
            # 其他目录正常复制
            cp -a "/root/$name/." "$PWD/"
        fi
    elif [ -f "/root/$name" ]; then
        cp -a "/root/$name" "$PWD/"
    else
        echo "错误: /root/$name 存在但不是有效文件或目录"
        exit 1
    fi

    # 给可执行文件赋权
    if [ -f "$PWD/$name" ]; then
        chmod +x "$PWD/$name"
    elif [ -d "$PWD/$name" ]; then
        find "$PWD/$name" -type f -exec chmod +x {} \;
    fi
}

# ==========================
# 下载组件
case "$MODE" in
    server_direct)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    server_argo)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        fetch_and_copy "cloudflared" "$CLOUDFLARED_URL"
        ;;
    client_tunnel)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    client_xray)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        fetch_and_copy "xray" "$XRAY_URL"
        ;;
    client_usque)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        fetch_and_copy "usque" "$USQUE_URL"
        ;;
    x-tunnel)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    dns-proxy)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        ;;
    usque)
        fetch_and_copy "usque" "$USQUE_URL"
        ;;
    *)
        echo "未知 MODE=$MODE"
        exit 1
        ;;
esac

# 如果USQUE=true且不在usque模式下，下载usque
if [ "$USQUE" == "true" ] && [ "$MODE" != "usque" ]; then
    fetch_and_copy "usque" "$USQUE_URL"
fi

# ===========================================
# 获取容器 IP
CONTAINER_IP=$(hostname -i | awk '{print $1}')

# ==============================================
# 输出启动模式信息
echo "============================================"
echo "容器启动模式 MODE=$MODE"
echo "============================================"

# 如果 dns-proxy 在当前模式下运行，则输出访问提示
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "client_usque" || "$MODE" == "dns-proxy" ]]; then
    echo "请登录 http://$CONTAINER_IP:10000 配置参数"
    echo "代理地址请改为socks5://127.0.0.1:3000"
fi

# ==========================
# 启动组件
# dns-proxy
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "client_usque" || "$MODE" == "dns-proxy" ]]; then
    echo "启动 dns-proxy 客户端..."
    ./dns-proxy >dns-proxy.log 2>&1 &
    DNS_PROXY_PID=$!
    DNS_PROXY_LOG="dns-proxy.log"
fi

# xray
if [[ "$MODE" == "client_xray" ]]; then
    echo "启动 xray 客户端..."
    ./xray run -config xray.json >xray.log 2>&1 &
    XRAY_PID=$!
    XRAY_LOG="xray.log"
fi

# usque
if [[ "$MODE" == "client_usque" || "$MODE" == "usque" || ("$USQUE" == "true" && "$MODE" != "usque") ]]; then
    echo "启动 usque 客户端..."
    ./usque socks -p 30001 >usque.log 2>&1 &
    USQUE_PID=$!
    USQUE_LOG="usque.log"
fi

# 启动 x-tunnel
if [[ "$MODE" == "server_direct" || "$MODE" == "server_argo" || "$MODE" == "client_tunnel" || "$MODE" == "x-tunnel" ]]; then
    # 根据模式选择配置文件
    if [[ "$MODE" == "server_direct" || "$MODE" == "server_argo" ]]; then
        XTUNNEL_CMD="./x-tunnel -config config_server.yaml"
    else
        XTUNNEL_CMD="./x-tunnel -config config.yaml"
    fi

    echo "启动 x-tunnel："
    echo "$XTUNNEL_CMD"

    $XTUNNEL_CMD >x-tunnel.log 2>&1 &
    XTUNNEL_LOG="x-tunnel.log"
fi

# 启动 cloudflared
if [[ "$MODE" == "server_argo" ]]; then
    CLOUDFLARED_CMD="./cloudflared"
    CLOUDFLARED_CONF="./cloudflared.txt"

    if [ -f "$CLOUDFLARED_CONF" ]; then
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # 跳过空行、注释、花括号
            [[ -z "$key" || "$key" == "{" || "$key" == "}" || "$key" =~ ^// ]] && continue
            [[ -z "$value" ]] && continue

            CLOUDFLARED_CMD="$CLOUDFLARED_CMD --$key $value"
        done < "$CLOUDFLARED_CONF"
    fi

    echo "启动 cloudflared："
    echo "$CLOUDFLARED_CMD"

    $CLOUDFLARED_CMD >cloudflared.log 2>&1 &
    CLOUDFLARED_LOG="cloudflared.log"
fi

# ==========================
# 检查并运行/root/s.sh脚本
if [ -f "/root/s.sh" ]; then
    echo "发现 /root/s.sh 脚本，准备执行..."
    chmod +x "/root/s.sh"
    echo "执行 /root/s.sh 脚本："
    bash "/root/s.sh"
fi


# ==========================
# 日志前台输出（优先级 x-tunnel > xray > usque > cloudflared > dns-proxy）
if [[ -n "$XTUNNEL_LOG" ]]; then
    tail -f "$XTUNNEL_LOG"
elif [[ -n "$XRAY_LOG" ]]; then
    tail -f "$XRAY_LOG"
elif [[ -n "$USQUE_LOG" ]]; then
    tail -f "$USQUE_LOG"
elif [[ -n "$CLOUDFLARED_LOG" ]]; then
    tail -f "$CLOUDFLARED_LOG"
elif [[ -n "$DNS_PROXY_LOG" ]]; then
    tail -f "$DNS_PROXY_LOG"
fi
