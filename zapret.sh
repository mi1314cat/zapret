#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "============================================================"
echo "🚀 Zapret2 v7.0 一键安装脚本（最终优化版）"
echo "============================================================"

# ============================================================
# 0. 检查 nft 是否可用
# ============================================================
echo "===> 检查 nft 原子加载能力..."

echo "table inet test { chain c { type filter hook input priority 0; } }" > /tmp/test.nft
if ! nft -f /tmp/test.nft >/dev/null 2>&1; then
    echo "❌ nft 不可用，切换到 iptables-legacy"
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
else
    echo "✔ nft 可用"
fi

# ============================================================
# 1. 克隆仓库（如果不存在）
# ============================================================
if [[ ! -d "$BASE" ]]; then
    echo "===> 克隆仓库..."
    mkdir -p /root/catmi
    cd /root/catmi
    git clone https://github.com/mi1314cat/zapret
    mv zapret/zapret2 Zapret2
fi

echo "✔ 仓库 OK"

# ============================================================
# 2. 下载最新 zapret2.sh（覆盖）
# ============================================================
echo "===> 下载最新 zapret2.sh..."
curl -fsSL "$REPO/zapret2.sh" -o "$BASE/zapret2.sh"
chmod +x "$BASE/zapret2.sh"

echo "✔ 菜单 OK"

# ============================================================
# X. 自动修复 zapret2.sh（防止递归 / 覆盖）
# ============================================================
echo "===> 检查 zapret2.sh 是否损坏..."

ZFILE="$BASE/zapret2.sh"
ZREPO="$REPO/zapret2.sh"

fix_zapret2() {
    echo "===> 正在恢复 zapret2.sh..."
    curl -fsSL "$ZREPO" -o "$ZFILE"
    chmod +x "$ZFILE"
    echo "✔ zapret2.sh 已恢复"
}

# 1. 文件不存在
if [[ ! -f "$ZFILE" ]]; then
    echo "❌ zapret2.sh 不存在"
    fix_zapret2
fi

# 2. 检查是否是递归版本（exec 自己）
if grep -qE '^exec .+zapret2\.sh' "$ZFILE"; then
    echo "❌ 检测到 zapret2.sh 是递归版本（exec 自己）"
    fix_zapret2
fi

# 3. 检查是否过短（被覆盖）
LINE_COUNT=$(wc -l < "$ZFILE")
if [[ "$LINE_COUNT" -lt 20 ]]; then
    echo "❌ zapret2.sh 内容异常（行数过少：$LINE_COUNT）"
    fix_zapret2
fi

# 4. 检查是否缺少 main_menu
if ! grep -q "main_menu" "$ZFILE"; then
    echo "❌ zapret2.sh 缺少 main_menu，可能损坏"
    fix_zapret2
fi

echo "✔ zapret2.sh 正常"

# ============================================================
# 3. 创建必要目录
# ============================================================
mkdir -p "$BASE/config"
mkdir -p "$BASE/config/nodes"
mkdir -p "$BASE/config/strategy.d"
mkdir -p "$BASE/logs"

echo "✔ 目录结构 OK"

# ============================================================
# 4. 默认配置（不会覆盖已有配置）
# ============================================================
create_if_missing() {
    local file="$1"
    local content="$2"
    if [[ ! -f "$file" ]]; then
        echo "创建默认配置：$file"
        echo "$content" > "$file"
    fi
}

# 端口
create_if_missing "$BASE/config/ports.conf" \
'TCP4_PORTS="80,443"
UDP4_PORTS="443"
TCP6_PORTS="80,443"
UDP6_PORTS="443"'

# NFQUEUE（正确默认）
create_if_missing "$BASE/config/pkt.conf" \
'QNUM=200
QSIZE=4096
TCP_PKT_IN="desync"
TCP_PKT_OUT="desync"
UDP_PKT_IN="none"
UDP_PKT_OUT="none"'

# 模式
create_if_missing "$BASE/config/mode.conf" "local"

# 默认策略（CF + Microsoft）
create_if_missing "$BASE/config/strategy.d/01-cloudflare.rule" \
'--tls-desync=fake
--tls-sni=www.cloudflare.com
--http-ua="Mozilla/5.0"
--http-host=www.cloudflare.com
--tls-sessionid=auto'

create_if_missing "$BASE/config/strategy.d/02-microsoft.rule" \
'--tls-desync=fake
--tls-sni=www.microsoft.com
--http-ua="Mozilla/5.0"
--http-host=www.microsoft.com
--tls-sessionid=auto'

# 默认白名单
create_if_missing "$BASE/config/whitelist.txt" ""

# 默认黑名单
create_if_missing "$BASE/config/blacklist.txt" \
'google.com
youtube.com
twitter.com
tiktok.com
cloudflare.com'

echo "✔ 默认配置 OK"

# ============================================================
# 5. 编译 nfqws2
# ============================================================
echo "===> 编译 nfqws2..."

if [[ ! -f "$BASE/bin/nfqws2" ]]; then
    bash "$BASE/lib/smart_build.sh"
fi

echo "✔ nfqws2 OK"

# ============================================================
# 6. 安装 systemd 服务
# ============================================================
echo "===> 安装 systemd 服务..."

cp "$BASE/service/zapret2.service" /etc/systemd/system/
systemctl daemon-reload

echo "✔ systemd OK"

# ============================================================
# 7. 加载防火墙
# ============================================================
echo "===> 加载防火墙..."

bash "$BASE/bin/firewallctl" clear || true
bash "$BASE/bin/firewallctl" apply

echo "✔ 防火墙 OK"

# ============================================================
# 8. 启动 zapret2d
# ============================================================
echo "===> 启动 zapret2d..."

systemctl enable --now zapret2

echo "✔ 服务 OK"

# ============================================================
# 9. 安装 catmiz CLI
# ============================================================
echo "===> 创建 catmiz 快捷方式..."

cat >/usr/local/bin/catmiz <<'EOF'
#!/usr/bin/env bash
bash /root/catmi/Zapret2/zapret2.sh "$@"
EOF

chmod +x /usr/local/bin/catmiz

echo "✔ 快捷方式已创建：现在可以直接输入 catmiz 打开菜单"



echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 安装完成！"
echo "👉 运行菜单：  catmiz"
echo "👉 查看状态：  systemctl status zapret2"
echo "============================================================"
