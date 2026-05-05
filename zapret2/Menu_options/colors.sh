RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
BOLD="\e[1m"
RESET="\e[0m"

ok()    { echo -e "${GREEN}[✔]${RESET} $1"; }
err()   { echo -e "${RED}[✘]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $1"; }
info()  { echo -e "${CYAN}[i]${RESET} $1"; }

title() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════╗"
    printf "║ %-42s ║\n" "$1"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}
