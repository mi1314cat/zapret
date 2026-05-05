#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

title "生成 hostlist/iplist"

> "$CFG/hostlist.txt"
> "$CFG/iplist.txt"

for f in "$CFG/nodes"/*.node; do
    [[ -f "$f" ]] || continue
    host=$(grep '^host=' "$f" | cut -d= -f2)

    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$host" >> "$CFG/iplist.txt"
    else
        echo "$host" >> "$CFG/hostlist.txt"
    fi
done

ok "hostlist/iplist 已生成"
read -rp "按回车继续..."
