#!/bin/bash
set -e

# ================================
# 0. 环境变量读取与默认值设置
# ================================
KOMARI_E="${E:-https://komari.ymj.de5.net}"
KOMARI_T="${T:-}"
CF_TOKEN="${CF:-}"
X="${X:-}"

# 创建一个专用的运行目录，确保非 root 用户有读写权限
RUN_DIR="/tmp/app_run"
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "==== 正在初始化环境... ===="

# ================================
# 1. 创建并运行 80 端口 AI 导航网页
# ================================
echo "正在创建 80 端口 AI 导航网页..."
WEB_DIR="$RUN_DIR/www"
mkdir -p "$WEB_DIR"

cat << 'EOF' > "$WEB_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Directory & Navigation</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: #1e293b;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --accent: #38bdf8;
            --accent-hover: #7dd3fc;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            margin: 0;
            padding: 40px 20px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(to right, #38bdf8, #818cf8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        p.subtitle {
            color: var(--text-muted);
            margin-bottom: 40px;
        }
        .container {
            max-width: 1200px;
            width: 100%;
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 25px;
        }
        .card {
            background-color: var(--card-bg);
            border: 1px solid #334155;
            border-radius: 12px;
            padding: 24px;
            transition: transform 0.2s, border-color 0.2s;
            text-decoration: none;
            color: inherit;
            display: flex;
            flex-direction: column;
        }
        .card:hover {
            transform: translateY(-4px);
            border-color: var(--accent);
        }
        .card h3 {
            margin: 0 0 10px 0;
            font-size: 1.3rem;
            color: var(--text-main);
        }
        .card p {
            margin: 0;
            font-size: 0.95rem;
            color: var(--text-muted);
            line-height: 1.5;
        }
        .tag {
            align-self: flex-start;
            background-color: #0284c7;
            color: white;
            font-size: 0.75rem;
            padding: 4px 8px;
            border-radius: 4px;
            margin-bottom: 12px;
            font-weight: bold;
            text-transform: uppercase;
        }
    </style>
</head>
<body>

    <h1>AI Navigation Hub</h1>
    <p class="subtitle">Quick access to the world's most popular AI tools and services.</p>

    <div class="container">
        <a href="https://chatgpt.com" target="_blank" class="card">
            <span class="tag">LLM / Chat</span>
            <h3>ChatGPT</h3>
            <p>OpenAI's flagship conversational AI, doskonały do writing, coding, and brainstorming.</p>
        </a>

        <a href="https://claude.ai" target="_blank" class="card">
            <span class="tag">LLM / Chat</span>
            <h3>Claude</h3>
            <p>Anthropic's advanced AI model known for deep reasoning, nuance, and long context coding.</p>
        </a>

        <a href="https://gemini.google.com" target="_blank" class="card">
            <span class="tag">LLM / Chat</span>
            <h3>Google Gemini</h3>
            <p>Google's multimodal AI chatbot, deeply integrated with Google search and workspace.</p>
        </a>

        <a href="https://chat.deepseek.com" target="_blank" class="card">
            <span class="tag">LLM / Reasoning</span>
            <h3>DeepSeek</h3>
            <p>An advanced open-source reasoning model optimized for math, coding, and logical tasks.</p>
        </a>

        <a href="https://www.perplexity.ai" target="_blank" class="card">
            <span class="tag">Search / Research</span>
            <h3>Perplexity AI</h3>
            <p>An AI-powered conversational search engine delivering summarized answers with inline citations.</p>
        </a>

        <a href="https://www.midjourney.com" target="_blank" class="card">
            <span class="tag">Image Generation</span>
            <h3>Midjourney</h3>
            <p>State-of-the-art text-to-image generator known for cinematic and highly artistic outputs.</p>
        </a>

        <a href="https://v0.dev" target="_blank" class="card">
            <span class="tag">AI Coding</span>
            <h3>v0 by Vercel</h3>
            <p>Generative UI system by Vercel that builds production-ready frontend code from text prompts.</p>
        </a>

        <a href="https://www.cursor.com" target="_blank" class="card">
            <span class="tag">AI Coding</span>
            <h3>Cursor</h3>
            <p>An AI-first code editor built on top of VS Code, optimizing developer velocity with smart completions.</p>
        </a>
    </div>

</body>
</html>
EOF

# 在后台启动 80 端口 HTTP 服务 (需要容器以 root 权限或赋予 80 端口绑定权限运行)
echo "正在后台启动 80 端口服务..."
python3 -m http.server 80 --directory "$WEB_DIR" &


# ================================
# 2. 运行 komari-agent
# ================================
if [ -n "$KOMARI_T" ]; then
    echo "正在启动 2. komari-agent..."
    
    # 下载指定的二进制文件
    wget -q -O komari-agent-linux-amd64 https://file.mor.cc.cd/komari/komari-agent-linux-amd64
    
    # 赋予执行权限
    chmod +x komari-agent-linux-amd64
    
    # 在后台带参数运行
    ./komari-agent-linux-amd64 -e "$KOMARI_E" -t "$KOMARI_T" &
else
    echo "未检测到环境变量 T，跳过 komari-agent 启动。"
fi

# ================================
# 3. 下载并运行 x-tunnel
# ================================
echo "正在下载 3. x-tunnel..."
wget -q -O x-tunnel-amd64 https://file.mor.cc.cd/x-tunnel/x-tunnel-amd64
chmod +x x-tunnel-amd64

if [ -n "$X" ]; then
    echo "检测到环境变量 X，正在带参数启动 x-tunnel..."
    ./x-tunnel-amd64 $X &
else
    echo "未检测到环境变量 X，正在后台默认启动 x-tunnel..."
    ./x-tunnel-amd64 &
fi

# ================================
# 4. 下载并运行 cloudflared
# ================================
echo "正在下载 4. cloudflared agent..."
wget -q -O systemd-networkd-agent-linux-amd64 https://file.mor.cc.cd/cloudflared/systemd-networkd-agent-linux-amd64
chmod +x systemd-networkd-agent-linux-amd64

if [ -n "$CF_TOKEN" ]; then
    echo "正在启动 4. cloudflared agent 并保持前台运行..."
    # 替换当前进程，作为容器的 PID 1 阻塞前台，防止容器退出
    exec ./systemd-networkd-agent-linux-amd64 tunnel --no-autoupdate run --token "$CF_TOKEN"
else
    echo "错误: 环境变量 CF 为空，cloudflared 无法启动！转为死循环以保持容器运行..."
    tail -f /dev/null
fi
