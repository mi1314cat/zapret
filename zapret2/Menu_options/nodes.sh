#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
source "$BASE/Menu_options/colors.sh"

node_menu() {
    while true; do
        clear
        title "节点管理"

        echo -e "${CYAN}编号 | 地址 | 端口${RESET}"
        echo "----------------------------------------"

        idx=1
        for f in "$CFG/nodes"/*.node; do
            [[ -f "$f" ]] || continue
            host=$(grep '^host=' "$f" | cut -d= -f2)
            port=$(grep '^port=' "$f" | cut -d= -f2)
            printf "${GREEN}%02d${RESET}) %-25s ${YELLOW}%s${RESET}\n" "$idx" "$host" "$port"
            idx=$((idx + 1))
        done

        echo "----------------------------------------"
        echo "1) 添加节点"
        echo "2) 删除节点"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1)
                read -rp "请输入节点地址（IP 或域名）：" host
                read -rp "请输入端口：" port
                num=$(ls "$CFG/nodes"/*.node 2>/dev/null | wc -l)
                num=$((num + 1))
                file="$CFG/nodes/$(printf "%02d" "$num").node"
                echo -e "host=$host\nport=$port" > "$file"
                ok "节点已添加：$host:$port"
                sleep 1
                ;;
            2)
                read -rp "请输入要删除的编号：" del
                file="$CFG/nodes/$(printf "%02d" "$del").node"
                [[ -f "$file" ]] && rm -f "$file" && ok "已删除" || err "不存在"
                sleep 1
                ;;
            0) return ;;
        esac
    done
}

node_menu
