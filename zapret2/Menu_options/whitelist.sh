#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 白名单管理（最终优化版）
# 支持：添加 / 删除 / 修改 / 自动编号 / 校验 / 并发锁
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
WL_FILE="$CFG/whitelist.txt"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_whitelist.lock"

touch "$WL_FILE"

# ============================================================
# 清理空行 + 去重
# ============================================================
clean_whitelist() {
    tmp=$(mktemp)
    grep -v '^[[:space:]]*$' "$WL_FILE" | sort -u > "$tmp"
    mv "$tmp" "$WL_FILE"
}

# ============================================================
# 自动重新编号（显示用，不改文件名）
# ============================================================
show_whitelist() {
    echo -e "${CYAN}编号 | 地址（域名/IP）${RESET}"
    echo "----------------------------------------"

    idx=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf "${GREEN}%02d${RESET}) %s\n" "$idx" "$line"
        idx=$((idx + 1))
    done < "$WL_FILE"

    echo "----------------------------------------"
}

# ============================================================
# 添加白名单
# ============================================================
add_whitelist() {
    read -rp "请输入域名或 IP：" addr
    [[ -z "$addr" ]] && err "不能为空" && return

    # 校验格式
    if ! is_ip "$addr" && ! is_domain "$addr"; then
        err "无效的域名或 IP"
        return
    fi

    echo "$addr" >> "$WL_FILE"
    clean_whitelist

    ok "已添加到白名单：$addr"
}

# ============================================================
# 删除白名单
# ============================================================
delete_whitelist() {
    read -rp "请输入要删除的编号：" del

    # 删除第 N 行
    if sed -i "${del}d" "$WL_FILE"; then
        clean_whitelist
        ok "已删除编号 $del"
    else
        err "删除失败或编号不存在"
    fi
}

# ============================================================
# 修改白名单条目
# ============================================================
edit_whitelist() {
    read -rp "请输入要修改的编号：" id

    old=$(sed -n "${id}p" "$WL_FILE" || true)
    [[ -z "$old" ]] && err "编号不存在" && return

    echo "当前条目：${YELLOW}$old${RESET}"
    read -rp "请输入新的域名或 IP：" new

    [[ -z "$new" ]] && err "不能为空" && return

    if ! is_ip "$new" && ! is_domain "$new"; then
        err "无效的域名或 IP"
        return
    fi

    sed -i "${id}s/.*/$new/" "$WL_FILE"
    clean_whitelist

    ok "已更新：$old → $new"
}

# ============================================================
# 主菜单
# ============================================================
whitelist_menu() {
    with_lock "$LOCK_FILE" _whitelist_menu_impl
}

_whitelist_menu_impl() {
    while true; do
        clear
        title "白名单管理（Zapret2 不处理这些域名/IP）"

        clean_whitelist
        show_whitelist

        echo "1) 添加白名单"
        echo "2) 删除白名单"
        echo "3) 修改白名单条目"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1) add_whitelist ;;
            2) delete_whitelist ;;
            3) edit_whitelist ;;
            0) return ;;
            *) err "无效选择" ;;
        esac

        sleep 1
    done
}

whitelist_menu
