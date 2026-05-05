#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "============================================================"
echo "🚀 Zapret2 v7.0 一键安装脚本（最终优化版）"
echo "============================================================"

# ============================================================
# 0. 安装依赖
# ============================================================
apt update -y
apt install -y git curl nftables iproute2

# ============================================================
# 1. 克隆仓库
# ============================================================
if [[ ! -d "$BASE" ]]; then
    mkdir -p /root/catmi
    cd /root/catmi
    git clone https://github.com/mi1314cat/zapret
    mv zapret/zapret2 Zapret2
fi

echo "✔ 仓库 OK"

# ============================================================
# 2. 修复权限
# ============================================================
chmod +x "$BASE"/bin/* || true
chmod +x "$BASE"/lib/*.sh || true
chmod +x "$BASE"/*.sh || true
chmod +x "$BASE"/Menu_options/*.sh || true

echo "✔ 权限修复 OK"

# ============================================================
# 3. 创建必要目录
# ============================================================
mkdir -p "$BASE/config"
mkdir -p "$BASE/config/nodes"
mkdir -p "$BASE/config/strategy.d"
mkdir -p "$BASE/logs"
mkdir -p /var/log/zapret2

echo "✔ 目录结构 OK"

# ============================================================
# 4. 自动生成 utils.sh（防止缺失）
# ============================================================
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
echo "✔ utils.sh OK"

# ============================================================
# 5. 自动生成默认配置
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
# 6. 自动生成白名单 + hostlist/iplist
# ============================================================
bash "$BASE/Menu_options/autowhitelist.sh" --silent || true
bash "$BASE/Menu_options/hostlist.sh" --silent || true

echo "✔ 白名单/hostlist/iplist OK"

# ============================================================
# 7. 安装 systemd 服务
# ============================================================
curl -fsSL "$REPO/service/zapret2.service" -o /etc/systemd/system/zapret2.service
systemctl daemon-reload

echo "✔ systemd 服务 OK"

# ============================================================
# 8. 加载防火墙
# ============================================================
bash "$BASE/bin/firewallctl" clear || true
bash "$BASE/bin/firewallctl" apply || true

echo "✔ 防火墙 OK"

# ============================================================
# 9. 启动 zapret2d
# ============================================================
systemctl enable --now zapret2 || err "服务启动失败，请检查 zapret2d"

echo "✔ zapret2 服务已启动"

# ============================================================
# 10. 安装 catmiz CLI
# ============================================================
cat >/usr/local/bin/catmiz <<'EOF'
#!/usr/bin/env bash
bash /root/catmi/Zapret2/zapret2.sh "$@"
EOF

chmod +x /usr/local/bin/catmiz
echo "✔ catmiz 快捷方式 OK"

# ============================================================
# 11. 清理临时目录
# ============================================================
rm -rf /root/catmi/zapret || true

echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 安装完成！"
echo "👉 运行菜单：  catmiz"
echo "👉 查看状态：  systemctl status zapret2"
echo "============================================================"
