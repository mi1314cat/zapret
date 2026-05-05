#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - utils.sh
# 通用工具库（日志、锁、执行器、校验）
# ============================================================

set -euo pipefail

# -------------------------------
# 颜色
# -------------------------------
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_RESET="\e[0m"

log_info()  { echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"; }
log_warn()  { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"; }
log_fatal() { echo -e "${COLOR_RED}[FATAL]${COLOR_RESET} $*"; exit 1; }

# -------------------------------
# 文件锁（避免并发）
# -------------------------------
lock_file="/tmp/zapret2.lock"

acquire_lock() {
    exec 200>"$lock_file"
    flock -n 200 || log_fatal "另一个 Zapret2 实例正在运行"
}

release_lock() {
    flock -u 200 || true
}

# -------------------------------
# 安全执行命令（带错误捕获）
# -------------------------------
run_cmd() {
    local desc="$1"
    shift
    if ! "$@"; then
        log_fatal "执行失败：$desc（命令：$*）"
    fi
}

# -------------------------------
# 路径检查
# -------------------------------
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

ensure_file() {
    [[ -f "$1" ]] || log_fatal "缺少必要文件：$1"
}

# -------------------------------
# JSON 安全输出（未来扩展）
# -------------------------------
json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g'
}

# -------------------------------
# root 检查
# -------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "必须使用 root 运行"
    fi
}
