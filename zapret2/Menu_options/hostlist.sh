#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - hostlist/iplist 生成器（最终优化版）
# 自动提取节点 + 策略中的域名/IP
# 支持静默模式 / 并发锁 / 自动去重 / 自动排序
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
NODES_DIR="$CFG/nodes"
STR_DIR="$CFG/strategy.d"

HOSTLIST="$CFG/hostlist.txt"
IPLIST="$CFG/iplist.txt"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_hostlist.lock"

# ============================================================
# 静默模式
# ============================================================
SILENT=0
[[ "${1:-}" == "--silent" ]] && SILENT=1

# ============================================================
# 提取域名
# ============================================================
extract_domains() {
    grep -Eo '([A-Za-z0-9-]+\.)+[A-Za-z]{2,}' | sort -u
}

# ============================================================
# 提取 IPv4 / IPv6
# ============================================================
extract_ips() {
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u
}

# ============================================================
# 核心逻辑：生成 hostlist/iplist
# ============================================================
generate_lists() {
    [[ $SILENT -eq 0 ]] && title "生成 hostlist / iplist"

    tmp_host=$(mktemp)
    tmp_ip=$(mktemp)

    # -----------------------------
    # 1. 从节点提取 host / IP
    # -----------------------------
    if [[ -d "$NODES_DIR" ]]; then
        for f in "$NODES_DIR"/*.node; do
            [[ -f "$f" ]] || continue
            host=$(grep '^host=' "$f" | cut -d= -f2)

            if is_ip "$host"; then
                echo "$host" >> "$tmp_ip"
            elif is_domain "$host"; then
                echo "$host" >> "$tmp_host"
            fi
        done
    fi

    # -----------------------------
    # 2. 从策略提取 host / IP
    # -----------------------------
    if [[ -d "$STR_DIR" ]]; then
        for f in "$STR_DIR"/*.rule; do
            [[ -f "$f" ]] || continue

            # 域名
            extract_domains < "$f" >> "$tmp_host"

            # IP
            extract_ips < "$f" >> "$tmp_ip"
        done
    fi

    # -----------------------------
    # 3. 去重 + 排序
    # -----------------------------
    sort -u "$tmp_host" > "$HOSTLIST"
    sort -u "$tmp_ip" > "$IPLIST"

    rm -f "$tmp_host" "$tmp_ip"

    # -----------------------------
    # 4. 输出结果
    # -----------------------------
    if [[ $SILENT -eq 0 ]]; then
        ok "hostlist/iplist 已生成："
        echo ""
        echo -e "${CYAN}hostlist.txt:${RESET}"
        cat "$HOSTLIST"
        echo ""
        echo -e "${CYAN}iplist.txt:${RESET}"
        cat "$IPLIST"
        echo ""
        read -rp "按回车返回..."
    fi
}

# ============================================================
# 主入口（带锁）
# ============================================================
with_lock "$LOCK_FILE" generate_lists
