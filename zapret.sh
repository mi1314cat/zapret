#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 一键引导脚本（自动调用 GitHub zapret2.sh）
# 包含：自动安装 + 自动配置 + 自动编译 + 自动修复 + 自动切换 iptables
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO_RAW="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "===> Zapret2 v7.0 一键引导脚本"
echo "===> 自动下载并调用 GitHub 菜单 zapret2.sh"

# ============================================================
# 0. 自动检测 nft 是否可用
# ============================================================
echo "===> 检查 nft 原子加载能力..."

echo "table inet test { chain c { type filter hook input priority 0; } }" > /tmp/test.nft
if ! nft -f /tmp/test.nft >/dev/null 2>&1; then
    echo "❌ nft 原子加载失败，系统不支持 nft 模式"
    echo "===> 自动切换到 iptables-legacy 模式..."

    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

    echo "===> 已切换到 iptables-legacy"
else
    echo "nft 原子加载正常，继续使用 nft 模式"
fi

# ============================================================
# 1. 克隆仓库（如果不存在）
# ============================================================
if [[ ! -d "$BASE" ]]; then
    echo "===> 未找到 $BASE，正在克隆仓库..."

    mkdir -p /root/catmi
    cd /root/catmi

    git clone https://github.com/mi1314cat/zapret || {
        echo "GitHub 克隆失败"
        exit 1
    }

    mv zapret/zapret2 Zapret2
    echo "===> 仓库已克隆到 /root/catmi/Zapret2"
fi

# ============================================================
# 2. 下载最新 zapret2.sh 菜单
# ============================================================
echo "===> 下载最新 zapret2.sh 菜单..."

curl -fsSL "$REPO_RAW/zapret2.sh" -o "$BASE/zapret2.sh" || {
    echo "下载 zapret2.sh 失败"
    exit 1
}

chmod +x "$BASE/zapret2.sh"

echo "菜单 OK"

# ============================================================
# 3. 创建必要目录
# ============================================================
echo "===> 创建必要目录..."

mkdir -p $BASE/config
mkdir -p $BASE/config/nodes/{argo,tuic,hy2}
mkdir -p $BASE/logs

echo "目录结构 OK"

# ============================================================
# 4. 自动生成默认配置（如果不存在）
# ============================================================
echo "===> 检查配置文件..."

create_if_missing() {
    local file="$1"
    local content="$2"

    if [[ ! -f "$file" ]]; then
        echo "创建默认配置：$file"
        echo "$content" > "$file"
    fi
}

create_if_missing "$BASE/config/ports.conf" \
'TCP4_PORTS="80,443"
UDP4_PORTS="443"
TCP6_PORTS="80,443"
UDP6_PORTS="443"'

create_if_missing "$BASE/config/pkt.conf" \
'TCP_PKT_IN="desync"
TCP_PKT_OUT="desync"
UDP_PKT_IN="none"
UDP_PKT_OUT="none"'

create_if_missing "$BASE/config/strategy.conf" \
'--tls-desync=fake
--tls-sni="www.microsoft.com"
--http-ua="Mozilla/5.0"
--http-host="www.microsoft.com"
--tls-sessionid=auto'

create_if_missing "$BASE/config/mode.conf" "local"

echo "配置文件 OK"

# ============================================================
# 5. 设置脚本执行权限
# ============================================================
echo "===> 设置脚本执行权限..."

chmod +x $BASE/bin/* || true
chmod +x $BASE/zapret2.sh || true

echo "权限 OK"

# ============================================================
# 6. 编译 nfqws2（自动调用 smart_build）
# ============================================================
echo "===> 编译 nfqws2..."

if [[ ! -f "$BASE/bin/nfqws2" ]]; then
    bash "$BASE/lib/smart_build.sh" || {
        echo "编译失败，自动回退"
        exit 1
    }
fi

echo "nfqws2 OK"

# ============================================================
# 7. 安装 systemd 服务
# ============================================================
echo "===> 安装 systemd 服务..."

cp "$BASE/service/zapret2.service" /etc/systemd/system/
systemctl daemon-reload

echo "systemd OK"

# ============================================================
# 8. 加载防火墙（第一次尝试）
# ============================================================
echo "===> 加载防火墙..."

if ! bash "$BASE/bin/firewallctl" apply; then
    echo "❌ 防火墙加载失败，启动自动修复流程..."

    echo "===> 自动切换到 iptables-legacy（再次确认）"
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

    echo "===> 清理旧防火墙规则..."
    bash "$BASE/bin/firewallctl" clear || true

    echo "===> 再次加载防火墙规则..."
    bash "$BASE/bin/firewallctl" apply || {
        echo "❌ 自动修复失败，请检查系统 iptables/nft 环境"
        exit 1
    }

    echo "自动修复成功！"
fi

echo "防火墙 OK"

# ============================================================
# 9. 启动 zapret2d
# ============================================================
echo "===> 启动 zapret2d..."

systemctl enable --now zapret2 || {
    echo "服务启动失败，自动回退"
    systemctl stop zapret2
    bash "$BASE/bin/firewallctl" clear
    exit 1
}
echo "===> 安装 catmiz CLI..."

cat >/usr/local/bin/catmiz <<'EOF'
#!/usr/bin/env bash

ZAPRET="/root/catmi/Zapret2/zapret2.sh"
SERVICE="zapret2"

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

help() {
    echo -e "${BLUE}catmiz - Zapret2 v7.0 CLI 工具${RESET}"
    echo ""
    echo -e "${GREEN}用法：${RESET}"
    echo "  catmiz                打开菜单"
    echo "  catmiz status         查看服务状态"
    echo "  catmiz restart        重启服务"
    echo "  catmiz stop           停止服务"
    echo "  catmiz start          启动服务"
    echo "  catmiz logs           查看实时日志"
    echo "  catmiz firewall       重新加载防火墙"
    echo "  catmiz fix            自动修复（编译 + 防火墙 + 服务）"
    echo "  catmiz build          重新编译 nfqws2 / zapret2d"
}

case "$1" in
    "" )
        exec "$ZAPRET"
        ;;
    status )
        systemctl status "$SERVICE"
        ;;
    restart )
        systemctl restart "$SERVICE"
        ;;
    stop )
        systemctl stop "$SERVICE"
        ;;
    start )
        systemctl start "$SERVICE"
        ;;
    logs )
        journalctl -u "$SERVICE" -f
        ;;
    firewall )
        /root/catmi/Zapret2/bin/firewallctl clear
        /root/catmi/Zapret2/bin/firewallctl apply
        ;;
    fix )
        /root/catmi/Zapret2/bin/fix
        ;;
    build )
        bash /root/catmi/Zapret2/lib/smart_build.sh
        ;;
    * )
        help
        ;;
esac
EOF

chmod +x /usr/local/bin/catmiz
echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 已成功启动！"
echo "你现在可以使用 GitHub 菜单："
echo ""
echo "    catmiz"
echo ""
echo "例如："
echo "    zapret2.sh status"
echo "    zapret2.sh strategy edit"
echo "    zapret2.sh mode gateway"
echo "============================================================"
