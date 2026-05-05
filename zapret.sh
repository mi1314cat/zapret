#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO_BASE="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "============================================================"
echo "🚀 Zapret2 v7.0 一键安装脚本（最终优化版，无需编译 nfqws2）"
echo "============================================================"

# ============================================================
# 0. 架构判断
# ============================================================
ARCH=$(uname -m)
echo "🔍 检测系统架构： $ARCH"

if [[ "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]]; then
    echo -e "\e[31m❌ 不支持的架构：$ARCH\e[0m"
    exit 1
fi

echo -e "\e[32m✔ 架构检测通过：$ARCH\e[0m"
echo ""

# ============================================================
# 1. 安装依赖
# ============================================================
apt update -y
apt install -y git curl nftables iproute2 build-essential pkg-config libmnl-dev libnetfilter-queue-dev

# ============================================================
# 2. 克隆仓库
# ============================================================
if [[ ! -d "$BASE" ]]; then
    mkdir -p /root/catmi
    cd /root/catmi
    git clone https://github.com/mi1314cat/zapret
    mv zapret/zapret2 Zapret2
fi

echo "✔ 仓库 OK"

# ============================================================
# 3. 修复权限
# ============================================================
chmod +x "$BASE"/bin/* || true
chmod +x "$BASE"/lib/*.sh || true
chmod +x "$BASE"/*.sh || true
chmod +x "$BASE"/Menu_options/*.sh || true

echo "✔ 权限修复 OK"

# ============================================================
# 4. 创建必要目录
# ============================================================
mkdir -p "$BASE/config"
mkdir -p "$BASE/config/nodes"
mkdir -p "$BASE/config/strategy.d"
mkdir -p "$BASE/logs"
mkdir -p /var/log/zapret2

echo "✔ 目录结构 OK"

# ============================================================
# 5. 自动生成 utils.sh（兜底）
# ============================================================
if [[ ! -f "$BASE/lib/utils.sh" ]]; then
    cat >"$BASE/lib/utils.sh" <<'EOF'
#!/usr/bin/env bash
ok()    { echo -e "[\e[32mOK\e[0m] $*"; }
warn()  { echo -e "[\e[33mWARN\e[0m] $*"; }
err()   { echo -e "[\e[31mERROR\e[0m] $*" >&2; }
info()  { echo -e "[\e[36mINFO\e[0m] $*"; }
log_info() { info "$@"; }

is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_domain() { [[ "$1" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]; }

with_lock() {
    local lock="$1"; shift
    exec 9>"$lock"
    flock -n 9 || { err "另一个实例正在运行"; return 1; }
    "$@"
    flock -u 9
}
EOF
    chmod +x "$BASE/lib/utils.sh"
fi
echo "✔ utils.sh OK"

# ============================================================
# 6. 自动生成默认配置
# ============================================================
echo "local" > "$BASE/config/mode.conf"

cat >"$BASE/config/ports.conf" <<EOF
port1=51610
port2=26095
EOF

cat >"$BASE/config/qnum.conf" <<EOF
qnum=100
qsize=4096
EOF

touch "$BASE/config/whitelist.txt"
touch "$BASE/config/blacklist.txt"
touch "$BASE/config/hostlist.txt"
touch "$BASE/config/iplist.txt"

echo "✔ 默认配置 OK"

# ============================================================
# 7. 自动生成白名单 + hostlist/iplist
# ============================================================
if [[ -x "$BASE/Menu_options/auto_whitelist.sh" ]]; then
    bash "$BASE/Menu_options/auto_whitelist.sh" --silent || true
fi
if [[ -x "$BASE/Menu_options/hostlist.sh" ]]; then
    bash "$BASE/Menu_options/hostlist.sh" --silent || true
fi

echo "✔ 白名单/hostlist/iplist OK"

# ============================================================
# 8. 安装 systemd 服务
# ============================================================
curl -fsSL "$REPO_BASE/service/zapret2.service" -o /etc/systemd/system/zapret2.service
systemctl daemon-reload

echo "✔ systemd 服务 OK"

# ============================================================
# 9. 自动下载 nfqws2（无需编译）
# ============================================================
NFQWS2="$BASE/bin/nfqws2"

echo "🔍 检查 nfqws2 是否存在..."

if [[ ! -x "$NFQWS2" ]]; then
    echo "⚠ 未找到 nfqws2，开始从 GitHub Releases 下载..."

    case "$ARCH" in
        aarch64)
            DOWNLOAD_URL="https://github.com/mi1314cat/zapret/releases/download/nfqws2/nfqws2_aarch64"
            ;;
        x86_64)
            DOWNLOAD_URL="https://github.com/mi1314cat/zapret/releases/download/nfqws2/nfqws2_amd"
            ;;
    esac

    mkdir -p "$BASE/bin"
    curl -L --fail "$DOWNLOAD_URL" -o "$NFQWS2"

    if [[ ! -s "$NFQWS2" ]]; then
        echo -e "\e[31m❌ 下载失败：$DOWNLOAD_URL\e[0m"
        exit 1
    fi

    chmod +x "$NFQWS2"
    echo -e "\e[32m✔ nfqws2 下载完成：$NFQWS2\e[0m"
else
    echo "✔ nfqws2 已存在，跳过下载"
fi

# ============================================================
# 10. 加载防火墙
# ============================================================
if [[ -x "$BASE/bin/firewallctl" ]]; then
    bash "$BASE/bin/firewallctl" clear || true
    bash "$BASE/bin/firewallctl" apply || true
fi

echo "✔ 防火墙 OK"

# ============================================================
# 11. 启动 zapret2d
# ============================================================
systemctl enable --now zapret2 || echo "⚠ 服务启动失败，请检查 zapret2d 日志"

echo "✔ zapret2 服务已启动（如无报错）"

# ============================================================
# 12. 安装 catmiz CLI
# ============================================================
cat >/usr/local/bin/catmiz <<'EOF'
#!/usr/bin/env bash
bash /root/catmi/Zapret2/zapret2.sh "$@"
EOF

chmod +x /usr/local/bin/catmiz
echo "✔ catmiz 快捷方式 OK"

# ============================================================
# 13. 清理临时目录
# ============================================================
rm -rf /root/catmi/zapret || true
rm -rf /tmp/zapret_build || true

echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 安装完成！"
echo "👉 运行菜单：  catmiz"
echo "👉 查看状态：  systemctl status zapret2"
echo "============================================================"
