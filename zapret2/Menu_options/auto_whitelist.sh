#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 自动生成白名单（节点 + 本地地址）
# 支持：静默模式 / 并发锁 / 自动去重 / 自动排序
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
NODES_DIR="$CFG/nodes"
WL_FILE="$CFG/whitelist.txt"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_autowhitelist.lock"

# ============================================================
# 静默模式
# ============================================================
SILENT=0
[[ "${1:-}" == "--silent" ]] && SILENT=1

# ============================================================
# 自动生成白名单（核心逻辑）
# ============================================================
generate_whitelist() {
    # 标题
    [[ $SILENT -eq 0 ]] && title "自动生成白名单（节点 + 本地地址）"

    tmp=$(mktemp)

    # -----------------------------
    # 1. 本地保留网段
    # -----------------------------
    LOCAL_NETS=(
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
    )

    for net in "${LOCAL_NETS[@]}"; do
        echo "$net" >> "$tmp"
    done

    # -----------------------------
    # 2. 本机 IPv4 / IPv6
    # -----------------------------
    ip -4 addr show scope global | awk '/inet /{split($2,a,"/");print a[1]}' >> "$tmp"
    ip -6 addr show scope global | awk '/inet6 /{split($2,a,"/");print a[1]}' >> "$tmp"

    # -----------------------------
    # 3. 节点 IP（自动加入）
    # -----------------------------
    if [[ -d "$NODES_DIR" ]]; then
        for f in "$NODES_DIR"/*.node; do
            [[ -f "$f" ]] || continue
            host=$(grep '^host=' "$f" | cut -d= -f2)

            # 只加入 IP，不加入域名
            if is_ip "$host"; then
                echo "$host" >> "$tmp"
            fi
        done
    fi

    # -----------------------------
    # 4. 去重 + 排序
    # -----------------------------
    sort -u "$tmp" > "$WL_FILE"
    rm -f "$tmp"

    # -----------------------------
    # 5. 输出结果
    # -----------------------------
    if [[ $SILENT -eq 0 ]]; then
        ok "白名单已自动生成（节点 + 本地地址）："
        echo ""
        cat "$WL_FILE"
        echo ""
        read -rp "按回车继续..."
    fi
}

# ============================================================
# 主入口（带锁）
# ============================================================
with_lock "$LOCK_FILE" generate_whitelist
