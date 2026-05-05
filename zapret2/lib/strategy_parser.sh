#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - strategy_parser.sh
# 完整引号解析器（支持空格、转义、blob）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ============================================================
# Mini Shell Parser（不使用 eval）
# 支持：
#   --foo="hello world"
#   --bar='x y z'
#   --blob="a b c\"d"
#   --raw=\x01\x02
# ============================================================

parse_strategy_line() {
    local line="$1"
    local -a tokens=()
    local buf=""
    local in_single=0
    local in_double=0
    local esc=0
    local c

    while IFS= read -r -n1 c; do
        if (( esc == 1 )); then
            buf+="$c"
            esc=0
            continue
        fi

        case "$c" in
            '\\')
                esc=1
                ;;
            "'")
                if (( in_double == 0 )); then
                    (( in_single = 1 - in_single ))
                else
                    buf+="$c"
                fi
                ;;
            '"')
                if (( in_single == 0 )); then
                    (( in_double = 1 - in_double ))
                else
                    buf+="$c"
                fi
                ;;
            ' ' | $'\t')
                if (( in_single == 0 && in_double == 0 )); then
                    if [[ -n "$buf" ]]; then
                        tokens+=("$buf")
                        buf=""
                    fi
                else
                    buf+="$c"
                fi
                ;;
            *)
                buf+="$c"
                ;;
        esac
    done <<< "$line"

    # 最后一个 token
    if [[ -n "$buf" ]]; then
        tokens+=("$buf")
    fi

    # 引号未闭合
    if (( in_single == 1 || in_double == 1 )); then
        log_fatal "strategy.conf 中存在未闭合的引号：$line"
    fi

    printf '%s\n' "${tokens[@]}"
}

# ============================================================
# 解析整个 strategy.conf
# 输出：每行一个“完整参数片段”
# ============================================================
parse_strategy_file() {
    local file="$1"
    ensure_file "$file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        parse_strategy_line "$line"
    done < "$file"
}
