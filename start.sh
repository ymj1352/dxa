#!/bin/bash
set -e

# ==========================
# 检测系统架构
ARCH=$(uname -m)
if [[ "$ARCH" == *"arm"* || "$ARCH" == *"aarch64"* ]]; then
    ARCH_TYPE="arm"
else
    ARCH_TYPE="x86"
fi
echo "检测到系统架构: $ARCH，使用 $ARCH_TYPE 版本组件"

# ==========================
# 下载地址声明（根据架构自动选择，环境变量优先）
XRAY_URL="${XRAY_URL:-https://dufs.f.mfs.cc.cd/data/$ARCH_TYPE/xray.tar.gz}"
DNS_PROXY_URL="${DNS_PROXY_URL:-https://dufs.f.mfs.cc.cd/data/$ARCH_TYPE/dns-proxy.tar.gz}"
X_TUNNEL_URL="${X_TUNNEL_URL:-https://dufs.f.mfs.cc.cd/data/$ARCH_TYPE/x-tunnel.tar.gz}"
CLOUDFLARED_URL="${CLOUDFLARED_URL:-https://dufs.f.mfs.cc.cd/data/$ARCH_TYPE/cloudflared.tar.gz}"
USQUE_URL="${USQUE_URL:-https://dufs.f.mfs.cc.cd/data/$ARCH_TYPE/usque.tar.gz}"

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
# 复制函数（优先级：/root > 网络下载）
fetch_and_copy() {
    local name="$1"
    local url="$2"
    local var_name=""
    local final_url=""
    local target_dir="/tmp"
    
    # 根据组件名称获取对应的环境变量名称和值
    case "$name" in
        "xray") 
            var_name="XRAY_URL" 
            final_url="${XRAY_URL}" 
            ;;
        "dns-proxy") 
            var_name="DNS_PROXY_URL" 
            final_url="${DNS_PROXY_URL}" 
            ;;
        "x-tunnel") 
            var_name="X_TUNNEL_URL" 
            final_url="${X_TUNNEL_URL}" 
            ;;
        "cloudflared") 
            var_name="CLOUDFLARED_URL" 
            final_url="${CLOUDFLARED_URL}" 
            ;;
        "usque") 
            var_name="USQUE_URL" 
            final_url="${USQUE_URL}" 
            ;;
        *) 
            var_name="UNKNOWN_URL" 
            final_url="$url" 
            ;;
    esac

    # 1. 首先检查/root目录（docker挂载文件夹）
    if [ -d "/root/$name" ]; then
        echo "使用 /root/$name 目录..."
    # 2. 从网络下载
    else
        echo "下载 $name 到 /root ..."
        echo "下载地址: $final_url"
        echo "正在下载... (超时时间: 2分钟)"
        cd /root
        
        # 清理之前的文件，避免冲突
        if [ -d "/root/$name" ]; then
            echo "清理旧的 /root/$name 目录..."
            rm -rf "/root/$name"
        fi
        if [ -f "/root/$name.tar.gz" ]; then
            echo "清理旧的 /root/$name.tar.gz 文件..."
            rm -f "/root/$name.tar.gz"
        fi
        
        # 使用wget下载，添加进度显示和超时设置
        if ! wget --timeout=120 --tries=3 --show-progress "$final_url" -O "$name.tar.gz"; then
            echo "\n错误: 下载 $name 失败，请检查网络连接或自定义下载地址"
            echo "提示: 请设置环境变量 $var_name 来指定自定义下载地址"
            echo "例如: docker run -e $var_name=https://your-custom-url/$ARCH_TYPE/$name.tar.gz ..."
            # 清理下载失败的文件
            rm -f "$name.tar.gz"
            exit 1
        fi
        
        echo "\n下载完成，正在解压..."
        if ! tar -xzf "$name.tar.gz"; then
            echo "错误: 解压 $name.tar.gz 失败"
            # 清理解压失败的文件
            rm -f "$name.tar.gz"
            exit 1
        fi
        # 清理压缩包
        rm -f "$name.tar.gz"
        
        # 验证解压后的文件是否存在
        if [ ! -e "/root/$name" ]; then
            echo "错误: /root/$name 不存在或解压失败"
            exit 1
        fi
    fi

    # 特殊处理 usque 组件
    if [ "$name" == "usque" ]; then
        # 确保 /root/usque 目录存在
        mkdir -p /root/usque
        
        # 检查是否有可执行文件
        if [ ! -f "/root/usque/usque" ]; then
            # 从下载的目录复制可执行文件
            if [ -f "/root/usque-$ARCH_TYPE/usque" ]; then
                echo "从 /root/usque-$ARCH_TYPE 复制到 /root/usque..."
                if ! cp -a /root/usque-$ARCH_TYPE/* /root/usque/; then
                    echo "错误: 复制 usque 文件失败"
                    exit 1
                fi
            else
                echo "错误: usque 可执行文件不存在"
                exit 1
            fi
        fi
        
        # 给可执行文件赋权
        if ! chmod +x /root/usque/usque; then
            echo "错误: 给 usque 可执行文件赋权失败"
            exit 1
        fi
        
        # 检查配置文件是否存在，最多尝试3次注册
        local register_attempts=0
        local max_attempts=3
        
        while [ ! -f "/root/usque/config.json" ] && [ $register_attempts -lt $max_attempts ]; do
            register_attempts=$((register_attempts + 1))
            echo "usque 配置文件不存在，正在第 $register_attempts 次注册..."
            # 在 /root/usque 目录内运行注册命令，自动输入y确认
            if ! (cd /root/usque && echo "y" | ./usque register); then
                echo "第 $register_attempts 次注册失败，等待2秒后重试..."
                sleep 2
            else
                # 检查注册是否成功
                if [ -f "/root/usque/config.json" ]; then
                    echo "注册成功！"
                    break
                else
                    echo "第 $register_attempts 次注册失败，等待2秒后重试..."
                    sleep 2
                fi
            fi
        done
        
        # 检查最终是否注册成功
        if [ ! -f "/root/usque/config.json" ]; then
            echo "错误: 经过 $max_attempts 次尝试，usque 注册失败"
            echo "跳过 usque 启动"
            # 设置一个标志，后续启动时跳过 usque
            SKIP_USQUE=true
            return
        fi
    fi

    # 复制到 /tmp 目录
    echo "从 /root/$name 复制到 $target_dir/ ..."
    # 清理目标目录
    if [ -d "$target_dir/$name" ]; then
        if ! rm -rf "$target_dir/$name"; then
            echo "错误: 清理目标目录失败"
            exit 1
        fi
    fi
    if [ -d "/root/$name" ]; then
        if ! cp -a "/root/$name" "$target_dir/"; then
            echo "错误: 复制 $name 目录失败"
            exit 1
        fi
    elif [ -f "/root/$name" ]; then
        if ! cp -a "/root/$name" "$target_dir/"; then
            echo "错误: 复制 $name 文件失败"
            exit 1
        fi
    else
        echo "错误: /root/$name 存在但不是有效文件或目录"
        exit 1
    fi

    # 给可执行文件赋权
    if [ -f "$target_dir/$name" ]; then
        if ! chmod +x "$target_dir/$name"; then
            echo "错误: 给 $name 可执行文件赋权失败"
            exit 1
        fi
    elif [ -d "$target_dir/$name" ]; then
        if ! find "$target_dir/$name" -type f -exec chmod +x {} \;; then
            echo "错误: 给 $name 目录内的可执行文件赋权失败"
            exit 1
        fi
        # 验证可执行文件是否存在
        if [ ! -f "$target_dir/$name/$name" ]; then
            echo "错误: $target_dir/$name/$name 可执行文件不存在"
            echo "请检查下载的文件结构是否正确"
            exit 1
        fi
    fi
    
    echo "$name 组件准备完成"
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
echo "==========================================="
echo "容器启动模式 MODE=$MODE"
echo "==========================================="

# 如果 dns-proxy 在当前模式下运行，则输出访问提示
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "client_usque" || "$MODE" == "dns-proxy" ]]; then
    echo "请登录 http://$CONTAINER_IP:10000 配置参数"
    echo "代理地址请改为socks5://127.0.0.1:XXXX  xray:10001 x-tunne:100002 usque:10003"
fi

# ==========================
# 启动组件
# dns-proxy
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "client_usque" || "$MODE" == "dns-proxy" ]]; then
    echo "启动 dns-proxy 客户端..."
    if [ -f "/tmp/dns-proxy/dns-proxy" ]; then
        # 清理旧的日志文件
        rm -f /tmp/dns-proxy.log
        # 在dns-proxy目录内启动
        (cd /tmp/dns-proxy && ./dns-proxy) >/tmp/dns-proxy.log 2>&1 &
        DNS_PROXY_PID=$!
        DNS_PROXY_LOG="/tmp/dns-proxy.log"
        echo "dns-proxy 启动成功，PID: $DNS_PROXY_PID"
        
        # 等待服务启动，增加等待时间
        sleep 3
        
        # 检查服务是否启动成功
        if ps -p $DNS_PROXY_PID > /dev/null 2>&1; then
            echo "dns-proxy 服务运行正常"
        else
            # 查看日志获取失败原因
            echo "错误: dns-proxy 启动失败，查看日志获取详细信息..."
            cat /tmp/dns-proxy.log
            # 继续执行脚本，不停止
        fi
    else
        echo "错误: /tmp/dns-proxy/dns-proxy 可执行文件不存在"
        exit 1
    fi
fi

# xray
if [[ "$MODE" == "client_xray" ]]; then
    echo "启动 x-ray 客户端..."
    if [ -f "/tmp/xray/xray" ]; then
        # 清理旧的日志文件
        rm -f /tmp/xray.log
        # 在xray目录内启动
        (cd /tmp/xray && ./xray run -config config.json) >/tmp/xray.log 2>&1 &
        XRAY_PID=$!
        XRAY_LOG="/tmp/xray.log"
        echo "x-ray 启动成功，PID: $XRAY_PID"
        # 等待服务启动
        sleep 3
        # 检查服务是否启动成功
        if ps -p $XRAY_PID > /dev/null 2>&1; then
            echo "x-ray 服务运行正常"
        else
            # 查看日志获取失败原因
            echo "错误: x-ray 启动失败，查看日志获取详细信息..."
            cat /tmp/xray.log
            # 继续执行脚本，不停止
        fi
    else
        echo "错误: /tmp/xray/xray 可执行文件不存在"
        exit 1
    fi
fi

# usque
if [[ "$MODE" == "client_usque" || "$MODE" == "usque" || ("$USQUE" == "true" && "$MODE" != "usque") ]]; then
    # 检查是否跳过 usque
    if [ "$SKIP_USQUE" == "true" ]; then
        echo "跳过 usque 启动（注册失败）"
    else
        echo "启动 usque 客户端..."
        # 直接在 /tmp/usque 目录内启动，使用端口10003
        if [ -f "/tmp/usque/usque" ]; then
            # 清理旧的日志文件
            rm -f /tmp/usque.log
            (cd /tmp/usque && ./usque socks -p 10003) >/tmp/usque.log 2>&1 &
            USQUE_PID=$!
            USQUE_LOG="/tmp/usque.log"
            echo "usque 启动成功，PID: $USQUE_PID"
            # 等待服务启动
            sleep 3
            # 检查服务是否启动成功
            if ps -p $USQUE_PID > /dev/null 2>&1; then
                echo "usque 服务运行正常"
            else
                # 查看日志获取失败原因
                echo "错误: usque 启动失败，查看日志获取详细信息..."
                cat /tmp/usque.log
                # 继续执行脚本，不停止
            fi
        else
            echo "错误: /tmp/usque/usque 可执行文件不存在"
            exit 1
        fi
    fi
fi

# 启动 x-tunnel
if [[ "$MODE" == "server_direct" || "$MODE" == "server_argo" || "$MODE" == "client_tunnel" || "$MODE" == "x-tunnel" ]]; then
    # 根据模式选择配置文件
    if [ -f "/tmp/x-tunnel/x-tunnel" ]; then
        # 清理旧的日志文件
        rm -f /tmp/x-tunnel.log
        if [[ "$MODE" == "server_direct" || "$MODE" == "server_argo" ]]; then
            # 在x-tunnel目录内启动
            (cd /tmp/x-tunnel && ./x-tunnel -config config_server.yaml) >/tmp/x-tunnel.log 2>&1 &
        else
            # 在x-tunnel目录内启动
            (cd /tmp/x-tunnel && ./x-tunnel -config config.yaml) >/tmp/x-tunnel.log 2>&1 &
        fi
        XTUNNEL_PID=$!
        XTUNNEL_LOG="/tmp/x-tunnel.log"
        echo "x-tunnel 启动成功，PID: $XTUNNEL_PID"
        # 等待服务启动
        sleep 3
        # 检查服务是否启动成功
        if ps -p $XTUNNEL_PID > /dev/null 2>&1; then
            echo "x-tunnel 服务运行正常"
        else
            # 查看日志获取失败原因
            echo "错误: x-tunnel 启动失败，查看日志获取详细信息..."
            cat /tmp/x-tunnel.log
            # 继续执行脚本，不停止
        fi
    else
        echo "错误: /tmp/x-tunnel/x-tunnel 可执行文件不存在"
        exit 1
    fi
fi

# 启动 cloudflared
if [[ "$MODE" == "server_argo" ]]; then
    if [ -f "/tmp/cloudflared/cloudflared" ]; then
        # 构建命令
        CLOUDFLARED_CMD="./cloudflared"
        CLOUDFLARED_CONF="cloudflared.txt"

        if [ -f "/tmp/cloudflared/$CLOUDFLARED_CONF" ]; then
            while IFS='=' read -r key value; do
                key=$(echo "$key" | tr -d ' ')
                value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                # 跳过空行、注释、花括号
                [[ -z "$key" || "$key" == "{" || "$key" == "}" || "$key" =~ ^// ]] && continue
                [[ -z "$value" ]] && continue

                CLOUDFLARED_CMD="$CLOUDFLARED_CMD --$key $value"
            done < "/tmp/cloudflared/$CLOUDFLARED_CONF"
        fi

        echo "启动 cloudflared："
        echo "$CLOUDFLARED_CMD"

        # 清理旧的日志文件
        rm -f /tmp/cloudflared.log
        # 在cloudflared目录内启动
        (cd /tmp/cloudflared && $CLOUDFLARED_CMD) >/tmp/cloudflared.log 2>&1 &
        CLOUDFLARED_PID=$!
        CLOUDFLARED_LOG="/tmp/cloudflared.log"
        echo "cloudflared 启动成功，PID: $CLOUDFLARED_PID"
        # 等待服务启动
        sleep 3
        # 检查服务是否启动成功
        if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
            echo "cloudflared 服务运行正常"
        else
            # 查看日志获取失败原因
            echo "错误: cloudflared 启动失败，查看日志获取详细信息..."
            cat /tmp/cloudflared.log
            # 继续执行脚本，不停止
        fi
    else
        echo "错误: /tmp/cloudflared/cloudflared 可执行文件不存在"
        exit 1
    fi
fi

# ==========================
# 检查并运行/root/s.sh脚本
if [ -f "/root/s.sh" ]; then
    echo "发现 /root/s.sh 脚本，准备执行..."
    chmod +x "/root/s.sh"
    echo "执行 /root/s.sh 脚本："
    if ! bash "/root/s.sh"; then
        echo "错误: /root/s.sh 脚本执行失败"
        # 继续执行脚本，不停止
    else
        echo "/root/s.sh 脚本执行成功"
    fi
fi



# ==========================
# 日志前台输出（优先级 x-tunnel > xray > usque > cloudflared > dns-proxy）
if [[ -n "$XTUNNEL_LOG" && -f "$XTUNNEL_LOG" ]]; then
    echo "正在查看 x-tunnel 日志..."
    tail -f "$XTUNNEL_LOG"
elif [[ -n "$XRAY_LOG" && -f "$XRAY_LOG" ]]; then
    echo "正在查看 x-ray 日志..."
    tail -f "$XRAY_LOG"
elif [[ -n "$USQUE_LOG" && -f "$USQUE_LOG" ]]; then
    echo "正在查看 usque 日志..."
    tail -f "$USQUE_LOG"
elif [[ -n "$CLOUDFLARED_LOG" && -f "$CLOUDFLARED_LOG" ]]; then
    echo "正在查看 cloudflared 日志..."
    tail -f "$CLOUDFLARED_LOG"
elif [[ -n "$DNS_PROXY_LOG" && -f "$DNS_PROXY_LOG" ]]; then
    echo "正在查看 dns-proxy 日志..."
    tail -f "$DNS_PROXY_LOG"
else
    echo "没有服务运行，退出..."
    # 不退出，继续执行
    sleep infinity
fi
