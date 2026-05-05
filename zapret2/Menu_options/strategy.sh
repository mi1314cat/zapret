#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
STR_DIR="$CFG/strategy.d"
mkdir -p "$STR_DIR"
source "$BASE/Menu_options/colors.sh"

strategy_menu() {
    while true; do
        clear
        title "策略管理"

        echo -e "${CYAN}编号 | 策略内容${RESET}"
        echo "----------------------------------------"

        idx=1
        for f in "$STR_DIR"/*.rule; do
            [[ -f "$f" ]] || continue
            rule=$(cat "$f")
            printf "${GREEN}%02d${RESET}) %s\n" "$idx" "$rule"
            idx=$((idx + 1))
        done

        echo "----------------------------------------"
        echo "1) 添加策略"
        echo "2) 删除策略"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1)
                read -rp "请输入策略内容：" rule
                num=$(ls "$STR_DIR"/*.rule 2>/dev/null | wc -l)
                num=$((num + 1))
                echo "$rule" > "$STR_DIR/$(printf "%02d" "$num").rule"
                ok "策略已添加"
                sleep 1
                ;;
            2)
                read -rp "请输入要删除的编号：" del
                file="$STR_DIR/$(printf "%02d" "$del").rule"
                [[ -f "$file" ]] && rm -f "$file" && ok "已删除" || err "不存在"
                sleep 1
                ;;
            0) return ;;
        esac
    done
}

strategy_menu
