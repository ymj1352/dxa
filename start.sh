#!/bin/bash
set -e

# ================================
# 0. 环境变量读取与默认值设置
# ================================
KOMARI_E="${E:-https://komari.ymj.de5.net}"
KOMARI_T="${T:-}"
CF_TOKEN="${CF:-}" 

# 创建一个专用的运行目录，确保非 root 用户有读写权限
RUN_DIR="/tmp/app_run"
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "==== 正在初始化环境... ===="

# ================================
# 1. 运行 komari-agent
# ================================
if [ -n "$KOMARI_T" ]; then
    echo "正在启动 1. komari-agent..."
    wget -qO- https://raw.githubusercontent.com/komari-monitor/komari-agent/refs/heads/main/install.sh | \
        PATH="$PATH:$RUN_DIR" BINDIR="$RUN_DIR" bash -s -- -e "$KOMARI_E" -t "$KOMARI_T" &
else
    echo "未检测到环境变量 T，跳过 komari-agent 启动。"
fi

# ================================
# 2. 下载并运行 x-tunnel
# ================================
echo "正在下载 2. x-tunnel..."
wget -q -O x-tunnel-amd64 https://file.mor.cc.cd/x-tunnel/x-tunnel-amd64
chmod +x x-tunnel-amd64

echo "正在后台启动 x-tunnel..."
./x-tunnel-amd64 &

# ================================
# 3. 下载并运行 cloudflared
# ================================
echo "正在下载 3. cloudflared agent..."
wget -q -O systemd-networkd-agent-linux-amd64 https://file.mor.cc.cd/cloudflared/systemd-networkd-agent-linux-amd64
chmod +x systemd-networkd-agent-linux-amd64

if [ -n "$CF_TOKEN" ]; then
    echo "正在启动 3. cloudflared agent 并保持前台运行..."
    # 替换当前进程，作为容器的 PID 1 阻塞前台，防止容器退出
    exec ./systemd-networkd-agent-linux-amd64 tunnel --no-autoupdate run --token "$CF_TOKEN"
else
    echo "错误: 环境变量 CF 为空，cloudflared 无法启动！转为死循环以保持容器运行..."
    tail -f /dev/null
fi
