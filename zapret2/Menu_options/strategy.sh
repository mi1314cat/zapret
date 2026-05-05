#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 策略管理（最终优化版）
# 支持：添加 / 删除 / 修改 / 自动编号 / 重排序 / 并发锁
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
STR_DIR="$CFG/strategy.d"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_strategy.lock"

ensure_dir "$STR_DIR"

# ============================================================
# 自动重新编号（01.rule、02.rule…）
# ============================================================
renumber_strategy() {
    local tmp
    tmp=$(mktemp)

    ls "$STR_DIR"/*.rule 2>/dev/null | sort > "$tmp" || true

    local idx=1
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        mv "$f" "$STR_DIR/$(printf "%02d" "$idx").rule"
        idx=$((idx + 1))
    done < "$tmp"

    rm -f "$tmp"
}

# ============================================================
# 显示策略列表
# ============================================================
show_strategy() {
    echo -e "${CYAN}编号 | 策略内容${RESET}"
    echo "----------------------------------------"

    local idx=1
    for f in "$STR_DIR"/*.rule; do
        [[ -f "$f" ]] || continue
        rule=$(cat "$f")
        printf "${GREEN}%02d${RESET}) %s\n" "$idx" "$rule"
        idx=$((idx + 1))
    done

    echo "----------------------------------------"
}

# ============================================================
# 添加策略
# ============================================================
add_strategy() {
    read -rp "请输入策略内容：" rule
    [[ -z "$rule" ]] && err "策略内容不能为空" && return

    local count
    count=$(ls "$STR_DIR"/*.rule 2>/dev/null | wc -l)
    count=$((count + 1))

    file="$STR_DIR/$(printf "%02d" "$count").rule"
    echo "$rule" > "$file"

    ok "策略已添加"

    renumber_strategy
}

# ============================================================
# 删除策略
# ============================================================
delete_strategy() {
    read -rp "请输入要删除的编号：" del
    file="$STR_DIR/$(printf "%02d" "$del").rule"

    if [[ -f "$file" ]]; then
        rm -f "$file"
        ok "已删除策略 $del"
        renumber_strategy
    else
        err "策略不存在"
    fi
}

# ============================================================
# 修改策略内容
# ============================================================
edit_strategy() {
    read -rp "请输入要修改的策略编号：" id
    file="$STR_DIR/$(printf "%02d" "$id").rule"

    [[ -f "$file" ]] || { err "策略不存在"; return; }

    echo "当前策略内容："
    echo -e "${YELLOW}$(cat "$file")${RESET}"
    echo ""

    read -rp "请输入新的策略内容：" new_rule
    [[ -z "$new_rule" ]] && err "策略内容不能为空" && return

    echo "$new_rule" > "$file"
    ok "策略 $id 已更新"
}

# ============================================================
# 主菜单
# ============================================================
strategy_menu() {
    with_lock "$LOCK_FILE" _strategy_menu_impl
}

_strategy_menu_impl() {
    while true; do
        clear
        title "策略管理"

        show_strategy

        echo "1) 添加策略"
        echo "2) 删除策略"
        echo "3) 修改策略内容"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1) add_strategy ;;
            2) delete_strategy ;;
            3) edit_strategy ;;
            0) return ;;
            *) warn "无效选择" ;;
        esac

        sleep 1
    done
}

strategy_menu
