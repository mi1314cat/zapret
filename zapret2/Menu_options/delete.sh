#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 完整卸载 / 删除脚本
# 删除所有 Zapret2 文件、配置、服务、规则
# ============================================================

BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
CFG="$BASE/config"
BIN="$BASE/bin"
SERVICE="zapret2"
PIDFILE="/run/zapret2.pid"

source "$MENU/colors.sh"

title "⚠️ 卸载 Zapret2（删除所有文件）"

echo -e "${RED}此操作将删除 Zapret2 的所有内容，包括：${RESET}"
echo ""
echo -e " ${YELLOW}- 主程序目录：$BASE${RESET}"
echo -e " ${YELLOW}- 所有配置文件${RESET}"
echo -e " ${YELLOW}- 所有节点、策略、hostlist/iplist${RESET}"
echo -e " ${YELLOW}- systemd 服务 zapret2${RESET}"
echo -e " ${YELLOW}- 防火墙规则${RESET}"
echo -e " ${YELLOW}- PID 文件${RESET}"
echo -e " ${YELLOW}- 日志文件${RESET}"
echo ""
echo -e "${RED}${BOLD}此操作不可恢复！${RESET}"
echo ""

read -rp "确认删除？输入 YES 才会继续：" confirm

if [[ "$confirm" != "YES" ]]; then
    warn "已取消删除操作"
    read -rp "按回车返回..."
    exit 0
fi

echo ""
warn "开始删除 Zapret2..."

# -----------------------------
# 停止服务
# -----------------------------
if systemctl is-active --quiet "$SERVICE"; then
    systemctl stop "$SERVICE"
    ok "已停止 zapret2 服务"
fi

# -----------------------------
# 删除 systemd 服务
# -----------------------------
if [[ -f "/etc/systemd/system/$SERVICE.service" ]]; then
    systemctl disable "$SERVICE" --now 2>/dev/null || true
    rm -f "/etc/systemd/system/$SERVICE.service"
    systemctl daemon-reload
    ok "已删除 systemd 服务"
fi

# -----------------------------
# 删除 PID 文件
# -----------------------------
if [[ -f "$PIDFILE" ]]; then
    rm -f "$PIDFILE"
    ok "已删除 PID 文件"
fi

# -----------------------------
# 清理防火墙规则
# -----------------------------
if [[ -x "$BIN/firewallctl" ]]; then
    "$BIN/firewallctl" clear || true
    ok "已清理防火墙规则"
fi

# -----------------------------
# 删除主目录
# -----------------------------
if [[ -d "$BASE" ]]; then
    rm -rf "$BASE"
    ok "已删除主目录：$BASE"
fi

# -----------------------------
# 删除日志
# -----------------------------
journalctl --rotate
journalctl --vacuum-time=1s
ok "已清理日志"

# -----------------------------
# 删除可执行文件（如果有）
# -----------------------------
rm -f /usr/local/bin/zapret2 2>/dev/null || true
rm -f /usr/bin/zapret2 2>/dev/null || true
ok "已清理可执行文件"

# -----------------------------
# 完成
# -----------------------------
echo ""
ok "Zapret2 已完全卸载并删除所有文件"
echo ""
read -rp "按回车返回主菜单..."
