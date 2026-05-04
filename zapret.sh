#!/usr/bin/env bash
# ============================================================
# Zapret2 专业版管理面板（模块化版）
# 作者：Copilot 为 Joshua 定制
#
# 本脚本目标：
#   1. 管理 Zapret2（nfqws2）服务
#   2. 配置 DPI 绕过策略（Lua）
#   3. 配置 NFQUEUE 端口
#   4. 管理多 Profile（hostlist）
#   5. 自动检测（blockcheck2）
#
# 本脚本特点：
#   - 模块化函数结构
#   - 可被主面板 source 调用
#   - 每个功能都有详细中文注释
#   - 适合专业用户扩展
# ============================================================

ZAPRET_DIR="/opt/zapret2"
ZAPRET_CFG="$ZAPRET_DIR/config"
SERVICE="nfqws2"

# -------------------------
# 颜色
# -------------------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"

msg() { echo -e "$1"; }
ok() { msg "${GREEN}[OK]${RESET} $1"; }
warn() { msg "${YELLOW}[WARN]${RESET} $1"; }
err() { msg "${RED}[ERR]${RESET} $1"; }

pause() { read -rp "按回车继续..." _; }

# -------------------------
# 基础检查
# -------------------------

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "请使用 root 运行此脚本"
    exit 1
  fi
}

check_zapret2() {
  if [[ ! -d "$ZAPRET_DIR" ]]; then
    err "未检测到 Zapret2 目录：$ZAPRET_DIR"
    err "请先安装 Zapret2：https://github.com/bol-van/zapret2"
    exit 1
  fi
}

systemd_has() {
  systemctl list-unit-files | grep -q "^$1.service"
}

# -------------------------
# systemd 控制
# -------------------------

start_zapret2() {
  if systemd_has "$SERVICE"; then
    systemctl start "$SERVICE" && ok "Zapret2 已启动" || err "启动失败"
  else
    err "未找到服务：$SERVICE.service"
  fi
}

stop_zapret2() {
  if systemd_has "$SERVICE"; then
    systemctl stop "$SERVICE" && ok "Zapret2 已停止" || err "停止失败"
  fi
}

restart_zapret2() {
  if systemd_has "$SERVICE"; then
    systemctl restart "$SERVICE" && ok "Zapret2 已重启" || err "重启失败"
  fi
}

status_zapret2() {
  if systemd_has "$SERVICE"; then
    systemctl status "$SERVICE" --no-pager
  else
    err "未找到服务：$SERVICE.service"
  fi
}
# ============================================================
# Part 2：NFQUEUE 端口配置 + 包处理数量 + DPI 策略（Lua）
# ============================================================

# ------------------------------------------------------------
# 端口配置（NFQUEUE）
# Zapret2 通过 NFQUEUE 拦截数据包，交给 nfqws2 处理。
# 你需要告诉 nfqws2：哪些端口的流量需要被“伪装/切包/乱序”。
#
# 例如：
#   TCP 443（TLS）
#   UDP 443（QUIC）
#   TCP 80（HTTP）
#   UDP 50000-50100（Discord）
# ------------------------------------------------------------

CFG_PORTS="$ZAPRET_CFG/ports.conf"

show_ports() {
  echo -e "${BLUE}当前 NFQUEUE 端口配置：${RESET}"
  if [[ -f "$CFG_PORTS" ]]; then
    cat "$CFG_PORTS"
  else
    warn "未找到 ports.conf"
  fi
}

set_ports() {
  echo -e "${BLUE}设置 NFQUEUE 端口（逗号分隔）${RESET}"
  read -rp "TCP 端口列表（如 80,443,7844）：" tcp
  read -rp "UDP 端口列表（如 443,50000-50100,7844）：" udp

  mkdir -p "$ZAPRET_CFG"

  cat > "$CFG_PORTS" <<EOF
# Zapret2 NFQUEUE 端口配置
TCP_PORTS="$tcp"
UDP_PORTS="$udp"
EOF

  ok "端口配置已更新"
  show_ports
}

reset_ports_default() {
  mkdir -p "$ZAPRET_CFG"
  cat > "$CFG_PORTS" <<EOF
TCP_PORTS="80,443,7844"
UDP_PORTS="443,50000-50100,7844"
EOF
  ok "端口已恢复默认"
  show_ports
}

# ------------------------------------------------------------
# 包处理数量（前 N 个包）
# DPI 通常只检查前几个包，因此我们只需要处理前 N 个包。
#
# 默认：
#   TCP 出站：9
#   TCP 入站：3
#   UDP 出站：9
#   UDP 入站：0
# ------------------------------------------------------------

CFG_PKT="$ZAPRET_CFG/pkt.conf"

show_pkt() {
  echo -e "${BLUE}当前包处理数量：${RESET}"
  if [[ -f "$CFG_PKT" ]]; then
    cat "$CFG_PKT"
  else
    warn "未找到 pkt.conf"
  fi
}

set_pkt() {
  read -rp "TCP 出站处理前 N 个包（默认 9）：" tcp_out
  read -rp "TCP 入站处理前 N 个包（默认 3）：" tcp_in
  read -rp "UDP 出站处理前 N 个包（默认 9）：" udp_out
  read -rp "UDP 入站处理前 N 个包（默认 0）：" udp_in

  tcp_out=${tcp_out:-9}
  tcp_in=${tcp_in:-3}
  udp_out=${udp_out:-9}
  udp_in=${udp_in:-0}

  mkdir -p "$ZAPRET_CFG"

  cat > "$CFG_PKT" <<EOF
TCP_PKT_OUT="$tcp_out"
TCP_PKT_IN="$tcp_in"
UDP_PKT_OUT="$udp_out"
UDP_PKT_IN="$udp_in"
EOF

  ok "包处理数量已更新"
  show_pkt
}

reset_pkt_default() {
  mkdir -p "$ZAPRET_CFG"
  cat > "$CFG_PKT" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="9"
UDP_PKT_IN="0"
EOF
  ok "包处理数量已恢复默认"
  show_pkt
}

# ------------------------------------------------------------
# DPI 策略（Lua）
# Zapret2 的核心：--lua-desync=xxx
#
# 你可以组合多个策略，例如：
#   fake + multisplit + md5sig
#
# 策略文件：$ZAPRET_CFG/strategy.conf
# ------------------------------------------------------------

CFG_STRATEGY="$ZAPRET_CFG/strategy.conf"

show_strategy() {
  echo -e "${BLUE}当前 DPI 策略（Lua）：${RESET}"
  if [[ -f "$CFG_STRATEGY" ]]; then
    cat "$CFG_STRATEGY"
  else
    warn "未找到 strategy.conf"
  fi
}

set_strategy_custom() {
  echo -e "${BLUE}请输入完整 Lua 策略参数（多行）${RESET}"
  echo "示例："
  echo "--lua-desync=fake:blob=fake_default_tls:fooling=md5sig"
  echo "--lua-desync=multisplit:pos=2"
  echo "输入完成后按 Ctrl+D 保存"
  echo

  mkdir -p "$ZAPRET_CFG"
  cat > "$CFG_STRATEGY"

  ok "自定义策略已保存"
  show_strategy
}

# ------------------------------------------------------------
# 预设策略（Minimal / Stable / Aggressive）
# ------------------------------------------------------------

apply_strategy_preset() {
  echo -e "${BLUE}选择预设策略：${RESET}"
  echo "1) Minimal（fake TLS）"
  echo "2) Stable（fake + multisplit + md5sig）"
  echo "3) Aggressive（fake + multisplit + multidisorder + md5sig）"
  echo "0) 返回"
  read -rp "选择：" opt

  mkdir -p "$ZAPRET_CFG"

  case "$opt" in
    1)
      cat > "$CFG_STRATEGY" <<EOF
--lua-desync=fake:blob=fake_default_tls
EOF
      ok "已应用 Minimal 策略"
      ;;
    2)
      cat > "$CFG_STRATEGY" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF
      ok "已应用 Stable 策略"
      ;;
    3)
      cat > "$CFG_STRATEGY" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
--lua-desync=multidisorder:pos=1
EOF
      ok "已应用 Aggressive 策略"
      ;;
    0) return ;;
    *) warn "无效选择" ;;
  esac

  show_strategy
}
# ============================================================
# Part 3：多 Profile 管理 + blockcheck2 + 卸载 + 主菜单
# ============================================================

# ------------------------------------------------------------
# 多 Profile 管理
# Zapret2 支持多策略链：
#
# nfqws2 \
#   --lua-desync=yt --hostlist=youtube.txt --new \
#   --lua-desync=dc --hostlist=discord.txt --new
#
# 每个 profile = 一个策略 + 一个 hostlist
# ------------------------------------------------------------

PROFILE_DIR="$ZAPRET_CFG/profiles"
mkdir -p "$PROFILE_DIR"

list_profiles() {
  echo -e "${BLUE}当前 Profiles：${RESET}"
  ls -1 "$PROFILE_DIR" 2>/dev/null || warn "没有任何 profile"
}

add_profile() {
  read -rp "Profile 名称（例如：yt 或 dc）：" name
  [[ -z "$name" ]] && { warn "名称不能为空"; return; }

  local dir="$PROFILE_DIR/$name"
  mkdir -p "$dir"

  echo -e "${BLUE}请输入 Lua 策略（多行，Ctrl+D 保存）${RESET}"
  cat > "$dir/strategy.conf"

  echo -e "${BLUE}请输入 hostlist 域名列表（多行，Ctrl+D 保存）${RESET}"
  cat > "$dir/hostlist.txt"

  ok "Profile [$name] 已创建"
}

delete_profile() {
  list_profiles
  read -rp "输入要删除的 Profile 名称：" name
  [[ -z "$name" ]] && return

  rm -rf "$PROFILE_DIR/$name"
  ok "Profile [$name] 已删除"
}

edit_profile() {
  list_profiles
  read -rp "输入要编辑的 Profile 名称：" name
  [[ -z "$name" ]] && return

  local dir="$PROFILE_DIR/$name"
  [[ ! -d "$dir" ]] && { err "Profile 不存在"; return; }

  echo "1) 编辑策略"
  echo "2) 编辑 hostlist"
  read -rp "选择：" opt

  case "$opt" in
    1) ${EDITOR:-nano} "$dir/strategy.conf" ;;
    2) ${EDITOR:-nano} "$dir/hostlist.txt" ;;
    *) warn "无效选择" ;;
  esac
}

# ------------------------------------------------------------
# blockcheck2（自动检测）
# Zapret2 自带 blockcheck2.sh，用于自动测试 DPI 绕过效果。
# ------------------------------------------------------------

run_blockcheck2() {
  if [[ ! -x "$ZAPRET_DIR/blockcheck2.sh" ]]; then
    err "未找到 blockcheck2.sh"
    return
  fi

  echo -e "${YELLOW}blockcheck2 将进行多轮 DPI 测试，可能需要几分钟...${RESET}"
  sleep 1
  (cd "$ZAPRET_DIR" && ./blockcheck2.sh)
}

# ------------------------------------------------------------
# 卸载（轻量）
# 不删除文件，只停止服务并清理 NFQUEUE 规则。
# ------------------------------------------------------------

uninstall_light() {
  warn "此操作将停止 Zapret2 并清理 NFQUEUE 规则，但不会删除文件。"
  read -rp "确认继续？(y/N)：" c
  [[ "$c" != "y" && "$c" != "Y" ]] && return

  stop_zapret2

  echo -e "${BLUE}尝试清理 iptables NFQUEUE 规则...${RESET}"
  iptables -t mangle -S | grep NFQUEUE | while read -r line; do
    iptables -t mangle ${line/^-A /-D }
  done

  ok "NFQUEUE 规则已清理"
}

# ------------------------------------------------------------
# 主菜单
# ------------------------------------------------------------

menu_main() {
  while true; do
    clear
    echo -e "${GREEN}===== Zapret2 专业版管理面板 =====${RESET}"
    echo "1) 启动 Zapret2"
    echo "2) 停止 Zapret2"
    echo "3) 重启 Zapret2"
    echo "4) 查看运行状态"
    echo "5) 配置端口（NFQUEUE）"
    echo "6) 配置包处理数量"
    echo "7) 配置 DPI 策略（Lua）"
    echo "8) 多 Profile 管理"
    echo "9) 查看防火墙规则"
    echo "10) 运行 blockcheck2"
    echo "11) 卸载（轻量）"
    echo "0) 退出"
    echo "====================================="
    read -rp "选择：" opt

    case "$opt" in
      1) start_zapret2; pause ;;
      2) stop_zapret2; pause ;;
      3) restart_zapret2; pause ;;
      4) status_zapret2; pause ;;
      5) menu_ports ;;
      6) menu_pkt ;;
      7) menu_strategy ;;
      8) menu_profiles ;;
      9) iptables -t mangle -L -n -v | sed -n '1,200p'; pause ;;
      10) run_blockcheck2; pause ;;
      11) uninstall_light; pause ;;
      0) exit 0 ;;
      *) warn "无效选择"; pause ;;
    esac
  done
}

# ------------------------------------------------------------
# 子菜单：端口
# ------------------------------------------------------------

menu_ports() {
  while true; do
    clear
    echo -e "${GREEN}--- NFQUEUE 端口配置 ---${RESET}"
    show_ports
    echo
    echo "1) 设置端口"
    echo "2) 恢复默认"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1) set_ports; pause ;;
      2) reset_ports_default; pause ;;
      0) break ;;
      *) warn "无效选择"; pause ;;
    esac
  done
}

# ------------------------------------------------------------
# 子菜单：包处理数量
# ------------------------------------------------------------

menu_pkt() {
  while true; do
    clear
    echo -e "${GREEN}--- 包处理数量 ---${RESET}"
    show_pkt
    echo
    echo "1) 设置"
    echo "2) 恢复默认"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1) set_pkt; pause ;;
      2) reset_pkt_default; pause ;;
      0) break ;;
      *) warn "无效选择"; pause ;;
    esac
  done
}

# ------------------------------------------------------------
# 子菜单：策略
# ------------------------------------------------------------

menu_strategy() {
  while true; do
    clear
    echo -e "${GREEN}--- DPI 策略（Lua） ---${RESET}"
    show_strategy
    echo
    echo "1) 应用预设策略"
    echo "2) 自定义策略"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1) apply_strategy_preset; pause ;;
      2) set_strategy_custom; pause ;;
      0) break ;;
      *) warn "无效选择"; pause ;;
    esac
  done
}

# ------------------------------------------------------------
# 子菜单：Profile
# ------------------------------------------------------------

menu_profiles() {
  while true; do
    clear
    echo -e "${GREEN}--- 多 Profile 管理 ---${RESET}"
    list_profiles
    echo
    echo "1) 添加 Profile"
    echo "2) 删除 Profile"
    echo "3) 编辑 Profile"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1) add_profile; pause ;;
      2) delete_profile; pause ;;
      3) edit_profile; pause ;;
      0) break ;;
      *) warn "无效选择"; pause ;;
    esac
  done
}

# ------------------------------------------------------------
# 程序入口
# ------------------------------------------------------------

main() {
  require_root
  check_zapret2
  menu_main
}

# 允许被 source 调用
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
