sudo tee /usr/local/bin/kconst > /dev/null << 'EOF'
#!/usr/bin/env bash
# kconst — Read compile-time constants from kernel header files
# Usage: kconst [OPTIONS] [header1.h header2.h ...]

set -euo pipefail

if [[ -t 1 ]]; then
    BOLD='\033[1m'; DIM='\033[2m'
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; RESET='\033[0m'
else
    BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; MAGENTA=''; RESET=''
fi

INCLUDE_ROOT="/usr/include"
FILTER=""
ALL_MODE=0
HEX_ONLY=0
SORT_MODE="name"

DEFAULT_HEADERS=(
    "linux/magic.h"
    "linux/sysrq.h"
    "linux/reboot.h"
    "asm/unistd.h"
)

REQUESTED_HEADERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            ALL_MODE=1
            shift ;;
        --filter|-f)
            FILTER="$2"
            shift 2 ;;
        --no-color)
            BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''
            CYAN=''; MAGENTA=''; RESET=''
            shift ;;
        --hex-only)
            HEX_ONLY=1
            shift ;;
        --sort)
            SORT_MODE="$2"
            shift 2 ;;
        --root)
            INCLUDE_ROOT="$2"
            shift 2 ;;
        --help|-h)
            cat <<HELP
Usage: kconst [OPTIONS] [header ...]

Read compile-time #define constants from kernel header files.

OPTIONS:
  --all              Scan every header under /usr/include/linux/
  --filter PATTERN   Only show constants whose name matches PATTERN (case-insensitive)
  --sort name|value  Sort output by name or numeric value (default: name)
  --hex-only         Print only NAME and HEX value, no descriptions or headers
  --no-color         Disable colour output
  --root PATH        Use a different include root (default: /usr/include)
  --help             Show this help

ARGUMENTS:
  header ...         One or more headers to scan, relative to include root
                     e.g.  linux/magic.h   asm/unistd.h

If no headers are given and --all is not set, the following are scanned:
  linux/magic.h
  linux/sysrq.h
  linux/reboot.h
  asm/unistd.h

EXAMPLES:
  kconst
  kconst linux/magic.h
  kconst --all --filter EXT
  kconst asm/unistd.h --sort value
  kconst linux/reboot.h --hex-only
HELP
            exit 0 ;;
        -*)
            echo "Unknown option: $1  (try --help)" >&2
            exit 1 ;;
        *)
            REQUESTED_HEADERS+=("$1")
            shift ;;
    esac
done

if [[ $ALL_MODE -eq 1 ]]; then
    mapfile -t HEADERS < <(find "${INCLUDE_ROOT}/linux" -name "*.h" | sort)
elif [[ ${#REQUESTED_HEADERS[@]} -gt 0 ]]; then
    HEADERS=()
    for h in "${REQUESTED_HEADERS[@]}"; do
        HEADERS+=("${INCLUDE_ROOT}/${h}")
    done
else
    HEADERS=()
    for h in "${DEFAULT_HEADERS[@]}"; do
        HEADERS+=("${INCLUDE_ROOT}/${h}")
    done
fi

if [[ ${#HEADERS[@]} -eq 0 ]]; then
    echo -e "${RED}No headers found.${RESET}" >&2
    exit 1
fi

if ! command -v cpp &>/dev/null; then
    echo -e "${RED}Error: 'cpp' (C preprocessor) is not installed.${RESET}" >&2
    echo "Install it with:  sudo apt install cpp    or    sudo dnf install gcc" >&2
    exit 1
fi

process_header() {
    local header_path="$1"
    local header_rel="${header_path#${INCLUDE_ROOT}/}"

    if [[ ! -f "$header_path" ]]; then
        echo -e "  ${RED}NOT FOUND:${RESET} $header_path" >&2
        return
    fi

    mapfile -t raw_defines < <(
        grep -E '^\s*#\s*define\s+[A-Z_][A-Z0-9_]+\s+' "$header_path" \
        | grep -v '(.*)'            \
        | grep -Ev '_H(\s|$)'       \
        | grep -Ev '__[A-Z_]+__'    \
        || true
    )

    if [[ ${#raw_defines[@]} -eq 0 ]]; then
        return
    fi

    declare -A name_to_val
    declare -A name_to_raw

    for line in "${raw_defines[@]}"; do
        name=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="#define"||$i=="define") {print $(i+1); exit}}' | grep -oE '^[A-Z_][A-Z0-9_]+')
        [[ -z "$name" ]] && continue

        if [[ -n "$FILTER" ]]; then
            echo "$name" | grep -qiE "$FILTER" || continue
        fi

        raw=$(echo "$line" | sed -E 's/^\s*#\s*define\s+[A-Z_][A-Z0-9_]+\s+//' | sed 's/\s*\/\*.*//' | xargs)

        expanded=$(echo "#include <${header_rel}>
_KCONST_VAL_ ${name}" \
            | cpp -I"${INCLUDE_ROOT}" -w -P 2>/dev/null \
            | grep '_KCONST_VAL_' \
            | sed 's/_KCONST_VAL_//' \
            | xargs \
            || true)

        if [[ -z "$expanded" ]] || ! echo "$expanded" | grep -qE '^-?[0-9]'; then
            if echo "$raw" | grep -qE '^(0[xX][0-9a-fA-F]+|-?[0-9]+)'; then
                expanded="$raw"
            else
                continue
            fi
        fi

        name_to_val["$name"]="$expanded"
        name_to_raw["$name"]="$raw"
    done

    if [[ ${#name_to_val[@]} -eq 0 ]]; then
        return
    fi

    if [[ $HEX_ONLY -eq 0 ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}┌─ ${header_rel} ${RESET}${DIM}(${header_path})${RESET}"
        printf "${BOLD}${CYAN}│${RESET}  %-45s  %-18s  %s\n" "CONSTANT" "HEX" "DECIMAL"
        echo -e "${CYAN}│${RESET}  $(printf '%.0s─' {1..80})"
    fi

    declare -a sort_list=()
    for name in "${!name_to_val[@]}"; do
        val="${name_to_val[$name]}"
        dec=$(printf '%d' "$val" 2>/dev/null || echo "0")
        if [[ "$SORT_MODE" == "value" ]]; then
            sort_list+=("$(printf '%020d' "$dec")|${name}")
        else
            sort_list+=("${name}|${name}")
        fi
    done

    mapfile -t sorted < <(printf '%s\n' "${sort_list[@]}" | sort)

    for entry in "${sorted[@]}"; do
        name="${entry##*|}"
        val="${name_to_val[$name]}"

        dec=$(printf '%d' "$val" 2>/dev/null || echo "?")
        if [[ "$dec" != "?" ]]; then
            hex=$(printf '0x%X' "$dec" 2>/dev/null || echo "$val")
        else
            hex="$val"
            dec="?"
        fi

        if [[ $HEX_ONLY -eq 1 ]]; then
            printf "%-45s  %s\n" "$name" "$hex"
        else
            printf "${CYAN}│${RESET}  ${BOLD}%-45s${RESET}  ${YELLOW}%-18s${RESET}  ${GREEN}%s${RESET}\n" \
                "$name" "$hex" "$dec"
        fi
    done

    if [[ $HEX_ONLY -eq 0 ]]; then
        echo -e "${CYAN}└─${RESET} ${DIM}${#name_to_val[@]} constants${RESET}"
    fi
}

if [[ $HEX_ONLY -eq 0 ]]; then
    echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${MAGENTA}║        Kernel Compile-Time Constants (from header files)         ║${RESET}"
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "  ${DIM}Include root : ${INCLUDE_ROOT}${RESET}"
    echo -e "  ${DIM}Kernel       : $(uname -r)${RESET}"
    [[ -n "$FILTER" ]] && echo -e "  ${DIM}Filter       : ${FILTER}${RESET}"
fi

for h in "${HEADERS[@]}"; do
    process_header "$h"
done

if [[ $HEX_ONLY -eq 0 ]]; then
    echo ""
fi
EOF
sudo chmod +x /usr/local/bin/kconst
