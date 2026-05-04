#!/usr/bin/env bash
# ============================================================
# Zapret2 专业版管理面板
# 作者：catmi
# 路径：/root/catmi/Zapret2
#
# 特点：
#   ✔ IPv4 + IPv6
#   ✔ iptables/ip6tables/nftables 自动识别
#   ✔ local / gateway 模式
#   ✔ 多队列 queue-balance（多核）
#   ✔ 动态策略加载（全局 + profile）
#   ✔ systemd 安全沙箱
#   ✔ NFQUEUE 规则随服务自动加载/卸载
#   ✔ blockcheck2 环境隔离
#   ✔ 小白友好菜单
# ============================================================

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
SERVICE="nfqws2"

# 默认 NFQUEUE 范围（多核）
QUEUE_START=200
QUEUE_END=203

# 默认模式：local（只处理本机 OUTPUT）
# 可选：gateway（PREROUTING + FORWARD）
MODE="local"

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
# 依赖检测（生产级）
# ============================================================

check_cmd() { command -v "$1" >/dev/null 2>&1; }

check_deps() {
  local missing=()

  for c in git make gcc lua5.4; do
    check_cmd "$c" || missing+=("$c")
  done

  if ! check_cmd iptables && ! check_cmd nft; then
    missing+=("iptables 或 nftables")
  fi

  if ((${#missing[@]} > 0)); then
    warn "缺少依赖：${missing[*]}"
    echo "将尝试自动安装（Debian/Ubuntu）"
    apt update || { err "apt update 失败"; exit 1; }
    apt install -y git make gcc lua5.4 iptables ip6tables nftables || {
      err "依赖安装失败，请检查环境"
      exit 1
    }
  fi
}

# ============================================================
# 安装 Zapret2（生产级）
# ============================================================

install_zapret2() {
  echo -e "${GREEN}开始安装 Zapret2 ...${RESET}"
  check_deps

  rm -rf "$ZAPRET2_DIR"
  git clone https://github.com/bol-van/zapret2 "$ZAPRET2_DIR" || {
    err "git clone 失败"
    exit 1
  }

  cd "$ZAPRET2_DIR" || exit 1
  make || { err "make 失败"; exit 1; }

  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"

  # 默认端口（IPv4 + IPv6）
  cat > "$ZAPRET2_CFG/ports.conf" <<EOF
TCP4_PORTS="443"
UDP4_PORTS=""
TCP6_PORTS="443"
UDP6_PORTS=""
EOF

  # 包处理数量
  cat > "$ZAPRET2_CFG/pkt.conf" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="0"
UDP_PKT_IN="0"
EOF

  # 全局策略（Stable）
  cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF

  # 模式
  echo "$MODE" > "$ZAPRET2_CFG/mode.conf"

  generate_run_script
  generate_firewall_scripts
  generate_systemd_service

  systemctl daemon-reload
  systemctl enable "$SERVICE"
  systemctl restart "$SERVICE"

  ok "Zapret2 安装完成！路径：$ZAPRET2_DIR"
}
# ============================================================
# Part 2：NFQUEUE 规则（IPv4/IPv6 + iptables/ip6tables/nftables）
# ============================================================

# 自动检测后端：优先 nftables（更现代）
detect_firewall_backend() {
  if command -v nft >/dev/null 2>&1; then
    echo "nft"
  elif command -v iptables >/dev/null 2>&1; then
    echo "iptables"
  else
    echo "none"
  fi
}

# ------------------------------------------------------------
# 生成 firewall/apply_rules.sh（随服务自动加载）
# ------------------------------------------------------------
generate_firewall_scripts() {
  mkdir -p "$ZAPRET2_DIR"

  # ========================= apply_rules.sh =========================
  cat > "$ZAPRET2_DIR/apply_rules.sh" <<'EOF'
#!/usr/bin/env bash
ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
QUEUE_START=200
QUEUE_END=203

backend="none"
if command -v nft >/dev/null 2>&1; then backend="nft"; fi
if command -v iptables >/dev/null 2>&1; then backend="iptables"; fi

source "$ZAPRET2_CFG/ports.conf"
MODE=$(cat "$ZAPRET2_CFG/mode.conf")

# 内网保护
SAFE_V4="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
SAFE_V6="::1/128 fe80::/10 fc00::/7"

# ---------------- nftables ----------------
if [[ "$backend" == "nft" ]]; then
  nft delete table inet zapret2 2>/dev/null
  nft add table inet zapret2

  # OUTPUT（本机流量）
  nft add chain inet zapret2 output "{ type filter hook output priority -150; }"

  # gateway 模式：PREROUTING + FORWARD
  if [[ "$MODE" == "gateway" ]]; then
    nft add chain inet zapret2 prerouting "{ type filter hook prerouting priority -150; }"
    nft add chain inet zapret2 forward "{ type filter hook forward priority -150; }"
  fi

  # IPv4 保护规则
  for net in $SAFE_V4; do
    nft add rule inet zapret2 output ip daddr $net return
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting ip daddr $net return
      nft add rule inet zapret2 forward ip daddr $net return
    fi
  done

  # IPv6 保护规则
  for net in $SAFE_V6; do
    nft add rule inet zapret2 output ip6 daddr $net return
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting ip6 daddr $net return
      nft add rule inet zapret2 forward ip6 daddr $net return
    fi
  done

  # 多队列
  QUEUE_RANGE="$QUEUE_START-$QUEUE_END"

  # IPv4 TCP
  if [[ -n "$TCP4_PORTS" ]]; then
    nft add rule inet zapret2 output tcp dport { $TCP4_PORTS } queue num $QUEUE_RANGE fanout
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting tcp dport { $TCP4_PORTS } queue num $QUEUE_RANGE fanout
      nft add rule inet zapret2 forward tcp dport { $TCP4_PORTS } queue num $QUEUE_RANGE fanout
    fi
  fi

  # IPv4 UDP
  if [[ -n "$UDP4_PORTS" ]]; then
    nft add rule inet zapret2 output udp dport { $UDP4_PORTS } queue num $QUEUE_RANGE fanout
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting udp dport { $UDP4_PORTS } queue num $QUEUE_RANGE fanout
      nft add rule inet zapret2 forward udp dport { $UDP4_PORTS } queue num $QUEUE_RANGE fanout
    fi
  fi

  # IPv6 TCP
  if [[ -n "$TCP6_PORTS" ]]; then
    nft add rule inet zapret2 output tcp dport { $TCP6_PORTS } queue num $QUEUE_RANGE fanout
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting tcp dport { $TCP6_PORTS } queue num $QUEUE_RANGE fanout
      nft add rule inet zapret2 forward tcp dport { $TCP6_PORTS } queue num $QUEUE_RANGE fanout
    fi
  fi

  # IPv6 UDP
  if [[ -n "$UDP6_PORTS" ]]; then
    nft add rule inet zapret2 output udp dport { $UDP6_PORTS } queue num $QUEUE_RANGE fanout
    if [[ "$MODE" == "gateway" ]]; then
      nft add rule inet zapret2 prerouting udp dport { $UDP6_PORTS } queue num $QUEUE_RANGE fanout
      nft add rule inet zapret2 forward udp dport { $UDP6_PORTS } queue num $QUEUE_RANGE fanout
    fi
  fi

  exit 0
fi

# ---------------- iptables/ip6tables ----------------
if [[ "$backend" == "iptables" ]]; then
  # 清理旧规则
  iptables -t mangle -S | grep ZAPRET2 | while read -r line; do
    iptables -t mangle ${line/^-A /-D }
  done
  ip6tables -t mangle -S | grep ZAPRET2 | while read -r line; do
    ip6tables -t mangle ${line/^-A /-D }
  done

  # IPv4 保护
  for net in $SAFE_V4; do
    iptables -t mangle -A OUTPUT -d $net -j RETURN -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      iptables -t mangle -A PREROUTING -d $net -j RETURN -m comment --comment "ZAPRET2"
      iptables -t mangle -A FORWARD -d $net -j RETURN -m comment --comment "ZAPRET2"
    fi
  done

  # IPv6 保护
  for net in $SAFE_V6; do
    ip6tables -t mangle -A OUTPUT -d $net -j RETURN -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      ip6tables -t mangle -A PREROUTING -d $net -j RETURN -m comment --comment "ZAPRET2"
      ip6tables -t mangle -A FORWARD -d $net -j RETURN -m comment --comment "ZAPRET2"
    fi
  done

  # 多队列
  QUEUE="--queue-num $QUEUE_START --queue-bypass"

  # IPv4 TCP
  if [[ -n "$TCP4_PORTS" ]]; then
    iptables -t mangle -A OUTPUT -p tcp -m multiport --dports $TCP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      iptables -t mangle -A PREROUTING -p tcp -m multiport --dports $TCP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
      iptables -t mangle -A FORWARD -p tcp -m multiport --dports $TCP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    fi
  fi

  # IPv4 UDP
  if [[ -n "$UDP4_PORTS" ]]; then
    iptables -t mangle -A OUTPUT -p udp -m multiport --dports $UDP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      iptables -t mangle -A PREROUTING -p udp -m multiport --dports $UDP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
      iptables -t mangle -A FORWARD -p udp -m multiport --dports $UDP4_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    fi
  fi

  # IPv6 TCP
  if [[ -n "$TCP6_PORTS" ]]; then
    ip6tables -t mangle -A OUTPUT -p tcp -m multiport --dports $TCP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      ip6tables -t mangle -A PREROUTING -p tcp -m multiport --dports $TCP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
      ip6tables -t mangle -A FORWARD -p tcp -m multiport --dports $TCP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    fi
  fi

  # IPv6 UDP
  if [[ -n "$UDP6_PORTS" ]]; then
    ip6tables -t mangle -A OUTPUT -p udp -m multiport --dports $UDP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    if [[ "$MODE" == "gateway" ]]; then
      ip6tables -t mangle -A PREROUTING -p udp -m multiport --dports $UDP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
      ip6tables -t mangle -A FORWARD -p udp -m multiport --dports $UDP6_PORTS -j NFQUEUE $QUEUE -m comment --comment "ZAPRET2"
    fi
  fi

  exit 0
fi
EOF

  chmod +x "$ZAPRET2_DIR/apply_rules.sh"

  # ========================= clear_rules.sh =========================
  cat > "$ZAPRET2_DIR/clear_rules.sh" <<'EOF'
#!/usr/bin/env bash
backend="none"
if command -v nft >/dev/null 2>&1; then backend="nft"; fi
if command -v iptables >/dev/null 2>&1; then backend="iptables"; fi

if [[ "$backend" == "nft" ]]; then
  nft delete table inet zapret2 2>/dev/null
  exit 0
fi

if [[ "$backend" == "iptables" ]]; then
  iptables -t mangle -S | grep ZAPRET2 | while read -r line; do
    iptables -t mangle ${line/^-A /-D }
  done
  ip6tables -t mangle -S | grep ZAPRET2 | while read -r line; do
    ip6tables -t mangle ${line/^-A /-D }
  done
  exit 0
fi
EOF

  chmod +x "$ZAPRET2_DIR/clear_rules.sh"

  ok "已生成 apply_rules.sh / clear_rules.sh（随服务自动加载/卸载）"
}
# ============================================================
# Part 3：run_nfqws2.sh（动态参数构建）
# ============================================================

generate_run_script() {
  cat > "$ZAPRET2_DIR/run_nfqws2.sh" <<'EOF'
#!/usr/bin/env bash
ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"

QUEUE_START=200
QUEUE_END=203

# 读取 pkt 配置
source "$ZAPRET2_CFG/pkt.conf"

# 参数数组
args=(
  "--queue-num=$QUEUE_START"
  "--queue-balance=$QUEUE_START-$QUEUE_END"
  "--queue-bypass"
  "--tcp-pkt-in=$TCP_PKT_IN"
  "--tcp-pkt-out=$TCP_PKT_OUT"
  "--udp-pkt-in=$UDP_PKT_IN"
  "--udp-pkt-out=$UDP_PKT_OUT"
)

# ---------------- 全局策略 ----------------
if [[ -f "$ZAPRET2_CFG/strategy.conf" ]]; then
  while read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    for token in $line; do
      args+=("$token")
    done
  done < "$ZAPRET2_CFG/strategy.conf"
fi

# ---------------- Profile 策略 ----------------
if [[ -d "$PROFILE_DIR" ]]; then
  for p in "$PROFILE_DIR"/*; do
    [[ -d "$p" ]] || continue

    # 策略
    if [[ -f "$p/strategy.conf" ]]; then
      while read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        for token in $line; do
          args+=("$token")
        done
      done < "$p/strategy.conf"
    fi

    # hostlist
    if [[ -f "$p/hostlist.txt" ]]; then
      args+=("--hostlist=$p/hostlist.txt")
    fi
  done
fi

exec "$ZAPRET2_DIR/nfqws2" "${args[@]}"
EOF

  chmod +x "$ZAPRET2_DIR/run_nfqws2.sh"
  ok "已生成 run_nfqws2.sh（动态参数构建）"
}

# ============================================================
# systemd（带安全沙箱）
# ============================================================

generate_systemd_service() {
  cat > /etc/systemd/system/"$SERVICE".service <<EOF
[Unit]
Description=Zapret2 nfqws2 DPI Bypass Service
After=network.target

[Service]
Type=simple
ExecStart=$ZAPRET2_DIR/run_nfqws2.sh
ExecStartPre=$ZAPRET2_DIR/apply_rules.sh
ExecStopPost=$ZAPRET2_DIR/clear_rules.sh

# 安全沙箱
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes
RestrictAddressFamilies=AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW

Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  ok "systemd 服务已生成（含安全沙箱）"
}

# ============================================================
# 节点 Profile 管理（策略选择 + hostlist）
# ============================================================

menu_node() {
  while true; do
    clear
    echo -e "${GREEN}--- 节点 DPI 绕过管理（Profile） ---${RESET}"
    echo "1) 启用节点 DPI 绕过"
    echo "2) 查看节点策略"
    echo "3) 删除节点 DPI 绕过"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1)
        read -rp "节点名称：" name
        read -rp "节点域名（如 cf.example.com）：" domain

        mkdir -p "$PROFILE_DIR/$name"

        echo "选择策略："
        echo "1) Minimal"
        echo "2) Stable"
        echo "3) Aggressive"
        read -rp "选择：" s

        case "$s" in
          1)
            echo "--lua-desync=fake:blob=fake_default_tls" > "$PROFILE_DIR/$name/strategy.conf"
            ;;
          2)
            cat > "$PROFILE_DIR/$name/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF
            ;;
          3)
            cat > "$PROFILE_DIR/$name/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
--lua-desync=multidisorder:pos=1
EOF
            ;;
        esac

        echo "$domain" > "$PROFILE_DIR/$name/hostlist.txt"

        ok "节点 [$name] 已启用 DPI 绕过"
        systemctl restart "$SERVICE"
        ;;
      2)
        read -rp "节点名称：" name
        if [[ -d "$PROFILE_DIR/$name" ]]; then
          echo -e "${BLUE}策略：${RESET}"
          cat "$PROFILE_DIR/$name/strategy.conf"
          echo -e "${BLUE}Hostlist：${RESET}"
          cat "$PROFILE_DIR/$name/hostlist.txt"
        else
          warn "节点未启用 DPI 绕过"
        fi
        ;;
      3)
        read -rp "节点名称：" name
        rm -rf "$PROFILE_DIR/$name"
        ok "节点 [$name] DPI 绕过已删除"
        systemctl restart "$SERVICE"
        ;;
      0) break ;;
    esac
    pause
  done
}

# ============================================================
# 全局策略管理
# ============================================================

menu_strategy() {
  while true; do
    clear
    echo -e "${GREEN}--- 全局 DPI 策略 ---${RESET}"
    cat "$ZAPRET2_CFG/strategy.conf"
    echo
    echo "1) 预设策略"
    echo "2) 自定义策略"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1)
        echo "1) Minimal"
        echo "2) Stable"
        echo "3) Aggressive"
        read -rp "选择：" p
        case "$p" in
          1)
            echo "--lua-desync=fake:blob=fake_default_tls" > "$ZAPRET2_CFG/strategy.conf"
            ;;
          2)
            cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF
            ;;
          3)
            cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
--lua-desync=multidisorder:pos=1
EOF
            ;;
        esac
        ok "策略已更新"
        ;;
      2)
        echo "输入策略（Ctrl+D 保存）："
        cat > "$ZAPRET2_CFG/strategy.conf"
        ok "策略已更新"
        ;;
      0) break ;;
    esac
    pause
  done
}

# ============================================================
# blockcheck2（环境隔离）
# ============================================================

run_blockcheck2() {
  echo -e "${YELLOW}准备运行 blockcheck2（将暂时清理 NFQUEUE 规则）${RESET}"
  "$ZAPRET2_DIR/clear_rules.sh"

  (cd "$ZAPRET2_DIR" && ./blockcheck2.sh)

  echo -e "${BLUE}恢复 NFQUEUE 规则...${RESET}"
  "$ZAPRET2_DIR/apply_rules.sh"
  ok "blockcheck2 完成"
}

# ============================================================
# 主菜单
# ============================================================

menu_main() {
  while true; do
    clear
    local status
    status=$(systemctl is-active "$SERVICE" 2>/dev/null)

    echo -e "${GREEN}===== Zapret2 专业版管理面板 v3 =====${RESET}"
    echo -e "服务状态：${BLUE}$status${RESET}"
    echo
    echo "1) 安装 Zapret2（自动）"
    echo "2) 启动 Zapret2"
    echo "3) 停止 Zapret2"
    echo "4) 重启 Zapret2"
    echo "5) 查看实时日志"
    echo "6) 配置 NFQUEUE 端口（IPv4/IPv6）"
    echo "7) 配置包处理数量"
    echo "8) 配置全局 DPI 策略"
    echo "9) 节点 DPI 绕过管理（Profile）"
    echo "10) 切换模式（local / gateway）"
    echo "11) 运行 blockcheck2（隔离环境）"
    echo "12) 卸载 Zapret2（干净删除）"
    echo "0) 退出"
    echo "====================================="
    read -rp "选择：" opt

    case "$opt" in
      1) install_zapret2; pause ;;
      2) systemctl start "$SERVICE"; pause ;;
      3) systemctl stop "$SERVICE"; pause ;;
      4) systemctl restart "$SERVICE"; pause ;;
      5) journalctl -u "$SERVICE" -f ;;
      6) menu_ports ;;
      7) menu_pkt ;;
      8) menu_strategy ;;
      9) menu_node ;;
      10)
        MODE=$(cat "$ZAPRET2_CFG/mode.conf")
        if [[ "$MODE" == "local" ]]; then
          echo "gateway" > "$ZAPRET2_CFG/mode.conf"
          ok "已切换为 gateway 模式（PREROUTING + FORWARD）"
        else
          echo "local" > "$ZAPRET2_CFG/mode.conf"
          ok "已切换为 local 模式（仅 OUTPUT）"
        fi
        systemctl restart "$SERVICE"
        pause
        ;;
      11) run_blockcheck2; pause ;;
      12) uninstall_zapret2; pause ;;
      0) exit 0 ;;
    esac
  done
}

# ============================================================
# 程序入口
# ============================================================

main() {
  require_root
  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"
  menu_main
}

main
