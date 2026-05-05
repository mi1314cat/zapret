#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

WL_FILE="$CFG/whitelist.txt"
touch "$WL_FILE"

whitelist_menu() {
    while true; do
        clear
        title "白名单管理（Zapret2 不处理这些域名/IP）"

        echo -e "${CYAN}编号 | 地址（域名/IP）${RESET}"
        echo "----------------------------------------"

        idx=1
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            printf "${GREEN}%02d${RESET}) %s\n" "$idx" "$line"
            idx=$((idx + 1))
        done < "$WL_FILE"

        echo "----------------------------------------"
        echo "1) 添加白名单"
        echo "2) 删除白名单"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1)
                read -rp "请输入域名或 IP：" addr
                echo "$addr" >> "$WL_FILE"
                ok "已添加到白名单：$addr"
                sleep 1
                ;;
            2)
                read -rp "请输入要删除的编号：" del
                sed -i "${del}d" "$WL_FILE"
                ok "已删除编号 $del"
                sleep 1
                ;;
            0) return ;;
            *) err "无效选择"; sleep 1 ;;
        esac
    done
}

whitelist_menu
