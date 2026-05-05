#!/usr/bin/env bash

# ================================
# 0. 静默模式检测
# ================================
SILENT=0
[[ "${1:-}" == "--silent" ]] && SILENT=1

# ================================
# 1. 加载环境
# ================================
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

WL_FILE="$CFG/whitelist.txt"

# ================================
# 2. 标题（非静默模式）
# ================================
[[ $SILENT -eq 0 ]] && title "自动生成白名单（本地地址）"

# 清空白名单
echo "" > "$WL_FILE"

# -----------------------------
# 3. 本地保留网段
# -----------------------------
LOCAL_NETS=(
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
)

for net in "${LOCAL_NETS[@]}"; do
    echo "$net" >> "$WL_FILE"
done

# -----------------------------
# 4. 本机 IP
# -----------------------------
ip -4 addr show scope global | awk '/inet /{split($2,a,"/");print a[1]}' >> "$WL_FILE"
ip -6 addr show scope global | awk '/inet6 /{split($2,a,"/");print a[1]}' >> "$WL_FILE"

# 去重
sort -u "$WL_FILE" -o "$WL_FILE"

# -----------------------------
# 5. 完成提示（非静默模式）
# -----------------------------
if [[ $SILENT -eq 0 ]]; then
    ok "白名单已自动生成（仅本地地址）："
    echo ""
    cat "$WL_FILE"
    echo ""
    read -rp "按回车继续..."
fi
