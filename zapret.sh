#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
REPO="https://raw.githubusercontent.com/mi1314cat/zapret/main/zapret2"

echo "============================================================"
echo "🚀 Zapret2 v7.0 一键安装脚本（最终优化版）"
echo "============================================================"

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
# 2. 修复权限（关键）
# ============================================================
chmod +x "$BASE"/bin/* || true
chmod +x "$BASE"/lib/*.sh || true

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
# 4. 安装 systemd 服务（最终版）
# ============================================================
curl -fsSL "$REPO/service/zapret2.service" -o /etc/systemd/system/zapret2.service
systemctl daemon-reload

echo "✔ systemd 服务 OK"

# ============================================================
# 5. 加载防火墙
# ============================================================
bash "$BASE/bin/firewallctl" clear || true
bash "$BASE/bin/firewallctl" apply

echo "✔ 防火墙 OK"

# ============================================================
# 6. 启动 zapret2d
# ============================================================
systemctl enable --now zapret2

echo "✔ zapret2 服务已启动"

# ============================================================
# 7. 安装 catmiz CLI（安全版）
# ============================================================
cat >/usr/local/bin/catmiz <<'EOF'
#!/usr/bin/env bash
bash /root/catmi/Zapret2/zapret2.sh "$@"
EOF

chmod +x /usr/local/bin/catmiz

echo "✔ catmiz 快捷方式 OK"

rm -rf /root/catmi/zapret

echo ""
echo "============================================================"
echo "🎉 Zapret2 v7.0 安装完成！"
echo "👉 运行菜单：  catmiz"
echo "👉 查看状态：  systemctl status zapret2"
echo "============================================================"
