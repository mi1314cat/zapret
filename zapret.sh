#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 一键引导脚本（自动调用 GitHub zapret2.sh）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO_RAW="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "===> Zapret2 v7.0 一键引导脚本"
echo "===> 自动下载并调用 GitHub 菜单 zapret2.sh"

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
# 5. 给脚本加执行权限
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
# 8. 加载防火墙
# ============================================================
echo "===> 加载防火墙..."

bash "$BASE/bin/firewallctl" apply || {
    echo "防火墙加载失败，自动回退"
    bash "$BASE/bin/firewallctl" clear
    exit 1
}

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

echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 已成功启动！"
echo "你现在可以使用 GitHub 菜单："
echo ""
echo "    /root/catmi/Zapret2/zapret2.sh"
echo ""
echo "例如："
echo "    zapret2.sh status"
echo "    zapret2.sh strategy edit"
echo "    zapret2.sh mode gateway"
echo "============================================================"
