#!/usr/bin/env bash
# ============================================================
# Zapret2 专业版管理面板（最终版）
# 作者：Copilot 为 Joshua 定制
# 路径：/root/catmi/Zapret2
# 面向小白用户：一键安装 / 管理 / 策略选择 / 节点联动 / 卸载
# ============================================================

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
SERVICE="nfqws2"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
msg() { echo -e "$1"; }
ok() { msg "${GREEN}[OK]${RESET} $1"; }
warn() { msg "${YELLOW}[WARN]${RESET} $1"; }
err() { msg "${RED}[ERR]${RESET} $1"; }
pause() { read -rp "按回车继续..." _; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "请使用 root 运行此脚本"
    exit 1
  fi
}

# ============================================================
# 自动安装 Zapret2（小白一键）
# ============================================================

install_zapret2() {
  echo -e "${GREEN}开始安装 Zapret2 ...${RESET}"

  apt update
  apt install -y git make gcc lua5.4 iptables nftables

  rm -rf "$ZAPRET2_DIR"
  git clone https://github.com/bol-van/zapret2 "$ZAPRET2_DIR"

  cd "$ZAPRET2_DIR"
  make

  mkdir -p "$ZAPRET2_CFG/profiles"

  cat > "$ZAPRET2_CFG/ports.conf" <<EOF
TCP_PORTS="443"
UDP_PORTS="443"
EOF

  cat > "$ZAPRET2_CFG/pkt.conf" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="9"
UDP_PKT_IN="0"
EOF

  cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls
EOF

  generate_systemd_service
  systemctl daemon-reload
  systemctl enable nfqws2
  systemctl restart nfqws2

  ok "Zapret2 安装完成！路径：$ZAPRET2_DIR"
}

# ============================================================
# 生成 systemd 服务
# ============================================================

generate_systemd_service() {
  mkdir -p "$ZAPRET2_CFG"
  cat > /etc/systemd/system/nfqws2.service <<EOF
[Unit]
Description=Zapret2 nfqws2 DPI Bypass Service
After=network.target

[Service]
Type=simple
ExecStart=$ZAPRET2_DIR/nfqws2 \\
  --queue-num=200 \\
  --queue-bypass \\
  --tcp-pkt-in=\$(grep TCP_PKT_IN $ZAPRET2_CFG/pkt.conf | cut -d'"' -f2) \\
  --tcp-pkt-out=\$(grep TCP_PKT_OUT $ZAPRET2_CFG/pkt.conf | cut -d'"' -f2) \\
  --udp-pkt-in=\$(grep UDP_PKT_IN $ZAPRET2_CFG/pkt.conf | cut -d'"' -f2) \\
  --udp-pkt-out=\$(grep UDP_PKT_OUT $ZAPRET2_CFG/pkt.conf | cut -d'"' -f2) \\
  \$(cat $ZAPRET2_CFG/strategy.conf) \\
  \$(for p in $ZAPRET2_CFG/profiles/*; do
      [ -d "\$p" ] || continue
      echo "--new"
      echo "--lua-desync=\$(basename \$p)"
      echo "--hostlist=\$p/hostlist.txt"
    done)

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  ok "systemd 服务已生成：/etc/systemd/system/nfqws2.service"
}

# ============================================================
# systemd 控制
# ============================================================

start_zapret2() { systemctl start nfqws2 && ok "已启动" || err "启动失败"; }
stop_zapret2() { systemctl stop nfqws2 && ok "已停止" || err "停止失败"; }
restart_zapret2() { systemctl restart nfqws2 && ok "已重启" || err "重启失败"; }
status_zapret2() { systemctl status nfqws2 --no-pager; }

view_realtime_log() {
  echo -e "${BLUE}正在查看实时日志（Ctrl+C 退出）${RESET}"
  journalctl -u nfqws2 -f
}

# ============================================================
# 端口配置
# ============================================================

CFG_PORTS="$ZAPRET2_CFG/ports.conf"

show_ports() { cat "$CFG_PORTS"; }

set_ports() {
  read -rp "TCP 端口：" tcp
  read -rp "UDP 端口：" udp
  cat > "$CFG_PORTS" <<EOF
TCP_PORTS="$tcp"
UDP_PORTS="$udp"
EOF
  ok "端口已更新"
}

reset_ports_default() {
  cat > "$CFG_PORTS" <<EOF
TCP_PORTS="443"
UDP_PORTS="443"
EOF
  ok "端口已恢复默认"
}

# ============================================================
# 包处理数量
# ============================================================

CFG_PKT="$ZAPRET2_CFG/pkt.conf"

show_pkt() { cat "$CFG_PKT"; }

set_pkt() {
  read -rp "TCP 出站（默认9）：" tcp_out
  read -rp "TCP 入站（默认3）：" tcp_in
  read -rp "UDP 出站（默认9）：" udp_out
  read -rp "UDP 入站（默认0）：" udp_in

  cat > "$CFG_PKT" <<EOF
TCP_PKT_OUT="${tcp_out:-9}"
TCP_PKT_IN="${tcp_in:-3}"
UDP_PKT_OUT="${udp_out:-9}"
UDP_PKT_IN="${udp_in:-0}"
EOF
  ok "包处理数量已更新"
}

reset_pkt_default() {
  cat > "$CFG_PKT" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="9"
UDP_PKT_IN="0"
EOF
  ok "已恢复默认"
}

# ============================================================
# DPI 策略（Lua）
# ============================================================

CFG_STRATEGY="$ZAPRET2_CFG/strategy.conf"

show_strategy() { cat "$CFG_STRATEGY"; }

set_strategy_custom() {
  echo "输入策略（Ctrl+D 保存）："
  cat > "$CFG_STRATEGY"
  ok "策略已更新"
}

apply_strategy_preset() {
  echo "1) Minimal"
  echo "2) Stable"
  echo "3) Aggressive"
  read -rp "选择：" opt

  case "$opt" in
    1)
      echo "--lua-desync=fake:blob=fake_default_tls" > "$CFG_STRATEGY"
      ;;
    2)
      cat > "$CFG_STRATEGY" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF
      ;;
    3)
      cat > "$CFG_STRATEGY" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
--lua-desync=multidisorder:pos=1
EOF
      ;;
  esac

  ok "策略已应用"
}

# ============================================================
# 节点联动：自动生成 Profile + hostlist
# ============================================================

create_profile_for_node() {
  local name="$1"
  local domain="$2"

  [[ -z "$name" || -z "$domain" ]] && { err "参数错误"; return; }

  local dir="$PROFILE_DIR/$name"
  mkdir -p "$dir"

  echo "--lua-desync=fake:blob=fake_default_tls:fooling=md5sig" > "$dir/strategy.conf"
  echo "--lua-desync=multisplit:pos=2" >> "$dir/strategy.conf"

  echo "$domain" > "$dir/hostlist.txt"

  ok "节点 [$name] 已启用 DPI 绕过"
  restart_zapret2
}

delete_profile_for_node() {
  local name="$1"
  rm -rf "$PROFILE_DIR/$name"
  ok "节点 [$name] 的 DPI 绕过已删除"
  restart_zapret2
}

show_profile_for_node() {
  local name="$1"
  local dir="$PROFILE_DIR/$name"

  if [[ ! -d "$dir" ]]; then
    warn "节点未启用 DPI 绕过"
    return
  fi

  echo -e "${BLUE}策略：${RESET}"
  cat "$dir/strategy.conf"
  echo
  echo -e "${BLUE}Hostlist：${RESET}"
  cat "$dir/hostlist.txt"
}

# ============================================================
# blockcheck2
# ============================================================

run_blockcheck2() {
  (cd "$ZAPRET2_DIR" && ./blockcheck2.sh)
}

# ============================================================
# 完整卸载
# ============================================================

uninstall_zapret2() {
  systemctl stop nfqws2
  systemctl disable nfqws2
  rm -f /etc/systemd/system/nfqws2.service
  systemctl daemon-reload

  iptables -t mangle -S | grep NFQUEUE | while read -r line; do
    iptables -t mangle ${line/^-A /-D }
  done

  rm -rf "$ZAPRET2_DIR"
  ok "Zapret2 已彻底卸载"
}

# ============================================================
# 菜单
# ============================================================

menu_main() {
  while true; do
    clear
    echo -e "${GREEN}===== Zapret2 专业版管理面板 =====${RESET}"
    echo "服务状态：$(systemctl is-active nfqws2)"
    echo
    echo "1) 安装 Zapret2（自动）"
    echo "2) 启动 Zapret2"
    echo "3) 停止 Zapret2"
    echo "4) 重启 Zapret2"
    echo "5) 查看实时日志"
    echo "6) 配置端口"
    echo "7) 配置包处理数量"
    echo "8) 配置 DPI 策略"
    echo "9) 节点 DPI 绕过管理"
    echo "10) 运行 blockcheck2"
    echo "11) 卸载 Zapret2（干净删除）"
    echo "0) 退出"
    read -rp "选择：" opt

    case "$opt" in
      1) install_zapret2; pause ;;
      2) start_zapret2; pause ;;
      3) stop_zapret2; pause ;;
      4) restart_zapret2; pause ;;
      5) view_realtime_log ;;
      6) menu_ports ;;
      7) menu_pkt ;;
      8) menu_strategy ;;
      9) menu_node ;;
      10) run_blockcheck2; pause ;;
      11) uninstall_zapret2; pause ;;
      0) exit 0 ;;
    esac
  done
}

menu_ports() {
  clear
  show_ports
  echo "1) 设置端口"
  echo "2) 恢复默认"
  read -rp "选择：" opt
  [[ "$opt" == "1" ]] && set_ports
  [[ "$opt" == "2" ]] && reset_ports_default
}

menu_pkt() {
  clear
  show_pkt
  echo "1) 设置"
  echo "2) 恢复默认"
  read -rp "选择：" opt
  [[ "$opt" == "1" ]] && set_pkt
  [[ "$opt" == "2" ]] && reset_pkt_default
}

menu_strategy() {
  clear
  show_strategy
  echo "1) 预设策略"
  echo "2) 自定义策略"
  read -rp "选择：" opt
  [[ "$opt" == "1" ]] && apply_strategy_preset
  [[ "$opt" == "2" ]] && set_strategy_custom
}

menu_node() {
  clear
  echo "1) 启用节点 DPI 绕过"
  echo "2) 查看节点策略"
  echo "3) 删除节点 DPI 绕过"
  read -rp "选择：" opt

  read -rp "节点名称：" name

  case "$opt" in
    1)
      read -rp "节点域名（如 cf.example.com）：" domain
      create_profile_for_node "$name" "$domain"
      ;;
    2)
      show_profile_for_node "$name"
      ;;
    3)
      delete_profile_for_node "$name"
      ;;
  esac
  pause
}

main() {
  require_root
  menu_main
}

main
