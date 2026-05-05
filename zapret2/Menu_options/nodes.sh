#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 节点管理（最终优化版）
# 支持：添加 / 删除 / 修改 host / 修改 port / 自动编号
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
NODES_DIR="$CFG/nodes"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_nodes.lock"

ensure_dir "$NODES_DIR"

# ============================================================
# 自动重新编号（01.node、02.node…）
# ============================================================
renumber_nodes() {
    local tmp
    tmp=$(mktemp)

    ls "$NODES_DIR"/*.node 2>/dev/null | sort > "$tmp" || true

    local idx=1
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        mv "$f" "$NODES_DIR/$(printf "%02d" "$idx").node"
        idx=$((idx + 1))
    done < "$tmp"

    rm -f "$tmp"
}

# ============================================================
# 显示节点列表
# ============================================================
show_nodes() {
    echo -e "${CYAN}编号 | 地址 | 端口${RESET}"
    echo "----------------------------------------"

    local idx=1
    for f in "$NODES_DIR"/*.node; do
        [[ -f "$f" ]] || continue
        host=$(grep '^host=' "$f" | cut -d= -f2)
        port=$(grep '^port=' "$f" | cut -d= -f2)
        printf "${GREEN}%02d${RESET}) %-25s ${YELLOW}%s${RESET}\n" "$idx" "$host" "$port"
        idx=$((idx + 1))
    done

    echo "----------------------------------------"
}

# ============================================================
# 添加节点
# ============================================================
add_node() {
    read -rp "请输入节点地址（IP 或域名）：" host
    [[ -z "$host" ]] && err "地址不能为空" && return

    read -rp "请输入端口：" port
    [[ -z "$port" ]] && err "端口不能为空" && return
    [[ "$port" =~ ^[0-9]+$ ]] || { err "端口必须是数字"; return; }

    if ! is_ip "$host" && ! is_domain "$host"; then
        err "无效的 IP 或域名"
        return
    fi

    local count
    count=$(ls "$NODES_DIR"/*.node 2>/dev/null | wc -l)
    count=$((count + 1))

    file="$NODES_DIR/$(printf "%02d" "$count").node"
    echo -e "host=$host\nport=$port" > "$file"

    ok "节点已添加：$host:$port"

    renumber_nodes
}

# ============================================================
# 删除节点
# ============================================================
delete_node() {
    read -rp "请输入要删除的编号：" del
    file="$NODES_DIR/$(printf "%02d" "$del").node"

    if [[ -f "$file" ]]; then
        rm -f "$file"
        ok "已删除节点 $del"
        renumber_nodes
    else
        err "节点不存在"
    fi
}

# ============================================================
# 修改节点 host
# ============================================================
edit_host() {
    read -rp "请输入要修改的节点编号：" id
    file="$NODES_DIR/$(printf "%02d" "$id").node"

    [[ -f "$file" ]] || { err "节点不存在"; return; }

    read -rp "请输入新的地址（IP 或域名）：" host
    [[ -z "$host" ]] && err "地址不能为空" && return

    if ! is_ip "$host" && ! is_domain "$host"; then
        err "无效的 IP 或域名"
        return
    fi

    sed -i "s/^host=.*/host=$host/" "$file"
    ok "节点 $id 的地址已更新为：$host"
}

# ============================================================
# 修改节点 port
# ============================================================
edit_port() {
    read -rp "请输入要修改的节点编号：" id
    file="$NODES_DIR/$(printf "%02d" "$id").node"

    [[ -f "$file" ]] || { err "节点不存在"; return; }

    read -rp "请输入新的端口：" port
    [[ -z "$port" ]] && err "端口不能为空" && return
    [[ "$port" =~ ^[0-9]+$ ]] || { err "端口必须是数字"; return; }

    sed -i "s/^port=.*/port=$port/" "$file"
    ok "节点 $id 的端口已更新为：$port"
}

# ============================================================
# 主菜单
# ============================================================
node_menu() {
    with_lock "$LOCK_FILE" _node_menu_impl
}

_node_menu_impl() {
    while true; do
        clear
        title "节点管理"

        show_nodes

        echo "1) 添加节点"
        echo "2) 删除节点"
        echo "3) 修改节点地址（host）"
        echo "4) 修改节点端口（port）"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1) add_node ;;
            2) delete_node ;;
            3) edit_host ;;
            4) edit_port ;;
            0) return ;;
            *) warn "无效选择" ;;
        esac

        sleep 1
    done
}

node_menu
