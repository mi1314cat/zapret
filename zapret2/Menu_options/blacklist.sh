#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 黑名单管理（最终优化版）
# 支持：添加 / 删除 / 修改 / 自动编号 / 校验 / 并发锁
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
BL_FILE="$CFG/blacklist.txt"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_blacklist.lock"

touch "$BL_FILE"

# ============================================================
# 清理空行 + 去重
# ============================================================
clean_blacklist() {
    tmp=$(mktemp)
    grep -v '^[[:space:]]*$' "$BL_FILE" | sort -u > "$tmp"
    mv "$tmp" "$BL_FILE"
}

# ============================================================
# 显示黑名单（自动编号）
# ============================================================
show_blacklist() {
    echo -e "${CYAN}编号 | 地址（域名/IP）${RESET}"
    echo "----------------------------------------"

    idx=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf "${GREEN}%02d${RESET}) %s\n" "$idx" "$line"
        idx=$((idx + 1))
    done < "$BL_FILE"

    echo "----------------------------------------"
}

# ============================================================
# 添加黑名单
# ============================================================
add_blacklist() {
    read -rp "请输入域名或 IP：" addr
    [[ -z "$addr" ]] && err "不能为空" && return

    # 校验格式
    if ! is_ip "$addr" && ! is_domain "$addr"; then
        err "无效的域名或 IP"
        return
    fi

    echo "$addr" >> "$BL_FILE"
    clean_blacklist

    ok "已添加到黑名单：$addr"
}

# ============================================================
# 删除黑名单
# ============================================================
delete_blacklist() {
    read -rp "请输入要删除的编号：" del

    if sed -i "${del}d" "$BL_FILE"; then
        clean_blacklist
        ok "已删除编号 $del"
    else
        err "删除失败或编号不存在"
    fi
}

# ============================================================
# 修改黑名单条目
# ============================================================
edit_blacklist() {
    read -rp "请输入要修改的编号：" id

    old=$(sed -n "${id}p" "$BL_FILE" || true)
    [[ -z "$old" ]] && err "编号不存在" && return

    echo "当前条目：${YELLOW}$old${RESET}"
    read -rp "请输入新的域名或 IP：" new

    [[ -z "$new" ]] && err "不能为空" && return

    if ! is_ip "$new" && ! is_domain "$new"; then
        err "无效的域名或 IP"
        return
    fi

    sed -i "${id}s/.*/$new/" "$BL_FILE"
    clean_blacklist

    ok "已更新：$old → $new"
}

# ============================================================
# 主菜单
# ============================================================
blacklist_menu() {
    with_lock "$LOCK_FILE" _blacklist_menu_impl
}

_blacklist_menu_impl() {
    while true; do
        clear
        title "黑名单管理（强制进入 Zapret2 DPI 处理）"

        clean_blacklist
        show_blacklist

        echo "1) 添加黑名单"
        echo "2) 删除黑名单"
        echo "3) 修改黑名单条目"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1) add_blacklist ;;
            2) delete_blacklist ;;
            3) edit_blacklist ;;
            0) return ;;
            *) err "无效选择" ;;
        esac

        sleep 1
    done
}

blacklist_menu
