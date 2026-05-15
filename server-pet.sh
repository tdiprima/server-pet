#!/usr/bin/env bash
#
# server-pet.sh — Tamagotchi-style Linux server dashboard for Mac terminal.
# Monitors remote Linux servers via SSH, shows health as a living creature.
# Run with no args for demo mode, or configure servers in SERVERS array.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Add servers as "user@host" entries. Empty = demo mode.
SERVERS=()

REFRESH_SECONDS=5

# Thresholds (percent)
CPU_WARN=70
CPU_CRIT=90
MEM_WARN=70
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=95

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ---------------------------------------------------------------------------
# Mood-based ASCII creatures
# ---------------------------------------------------------------------------

creature_happy() {
    cat <<'ART'
    ╔═══════╗
    ║ ^   ^ ║
    ║  ╰─╯  ║
    ║  ───  ║
    ╚═══════╝
     /|   |\
ART
}

creature_okay() {
    cat <<'ART'
    ╔═══════╗
    ║ •   • ║
    ║  ╰─╯  ║
    ║  ───  ║
    ╚═══════╝
     /|   |\
ART
}

creature_worried() {
    cat <<'ART'
    ╔═══════╗
    ║ ◦   ◦ ║
    ║  ╰─╯  ║
    ║  ~~~  ║
    ╚═══════╝
     /|   |\
      ^^^
ART
}

creature_stressed() {
    cat <<'ART'
    ╔═══════╗
    ║ ×   × ║
    ║  ╰─╯  ║
    ║  ≈≈≈  ║
    ╚═══════╝
    /||   ||\
     !!! !!!
ART
}

creature_dead() {
    cat <<'ART'
    ╔═══════╗
    ║ x   x ║
    ║  ╰─╯  ║
    ║  ___  ║
    ╚═══════╝
       ___
      / R \
      \ I /
      | P |
ART
}

creature_sleeping() {
    cat <<'ART'
    ╔═══════╗  z
    ║ -   - ║   z
    ║  ╰─╯  ║    z
    ║  ───  ║
    ╚═══════╝
     /|   |\
ART
}

# ---------------------------------------------------------------------------
# Status messages — personality layer
# ---------------------------------------------------------------------------

msg_happy=(
    "Servers humming. Life good."
    "All green. Pet server happy."
    "Uptime strong. Server flex."
    "No alerts. Server take nap? No. Server WORK."
    "CPU cool. RAM chill. Disk spacious. Vibes immaculate."
    "Server so healthy it could run Crysis."
    "Zero warnings. Server employee of month."
)

msg_okay=(
    "Things fine. Mostly. Don't look too close."
    "Server doing its best. Respect that."
    "Minor blips. Nothing coffee can't fix."
    "Server says: 'I'm fine.' (narrator: it was mostly fine)"
    "Holding steady. Like that one load-bearing intern."
)

msg_worried=(
    "Server sweating a little. Maybe check on it?"
    "Resources getting tight. Server needs a hug."
    "Warning lights on. Server entering its villain arc."
    "Things are... concerning. Like a cat near a glass."
    "Server making the face your sysadmin makes before PTO."
)

msg_stressed=(
    "SERVER NOT OKAY. REPEAT: NOT OKAY."
    "Everything is on fire. This is fine. (It is not fine.)"
    "Server screaming internally. And externally. Check logs."
    "Mayday. Disk is full. RAM is full. Cup is empty."
    "Server has entered the 'send help' phase."
)

msg_dead=(
    "Server has left the chat."
    "Press F to pay respects."
    "Server is with the cloud angels now."
    "Connection refused. Server refuses to even."
)

msg_sleeping=(
    "Server sleeping. Shh. Don't wake it."
    "Low activity. Server dreaming of packets."
    "Quiet hours. Server counts sheep (processes)."
)

pick_random() {
    local -n arr=$1
    local count="${#arr[@]}"
    echo "${arr[$((RANDOM % count))]}"
}

# ---------------------------------------------------------------------------
# Data collection
# ---------------------------------------------------------------------------

get_demo_data() {
    local hour
    hour=$(date +%H)

    local cpu_base mem_base disk_base load_avg uptime_str
    cpu_base=$((RANDOM % 40 + 10))
    mem_base=$((RANDOM % 30 + 30))
    disk_base=$((RANDOM % 20 + 40))
    load_avg="0.$((RANDOM % 9))$((RANDOM % 9))"

    local days=$((RANDOM % 200 + 1))
    local hours=$((RANDOM % 24))
    local mins=$((RANDOM % 60))
    uptime_str="${days}d ${hours}h ${mins}m"

    local procs=$((RANDOM % 150 + 80))
    local net_in="$((RANDOM % 500 + 10)) KB/s"
    local net_out="$((RANDOM % 300 + 5)) KB/s"
    local swap=$((RANDOM % 15))

    # Simulate spikes
    if ((RANDOM % 10 == 0)); then
        cpu_base=$((RANDOM % 20 + 80))
    fi
    if ((RANDOM % 15 == 0)); then
        mem_base=$((RANDOM % 15 + 85))
    fi

    echo "DEMO|demo-srv-01|${cpu_base}|${mem_base}|${disk_base}|${load_avg}|${uptime_str}|${procs}|${net_in}|${net_out}|${swap}"
}

get_server_data() {
    local server="$1"
    local host_label
    host_label=$(echo "${server}" | cut -d'@' -f2)

    local result
    result=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${server}" '
        cpu=$(top -bn1 | grep "Cpu(s)" | awk "{print 100 - \$8}" | cut -d. -f1)
        mem=$(free | awk "/Mem:/ {printf \"%.0f\", \$3/\$2 * 100}")
        disk=$(df / | awk "NR==2 {print \$5}" | tr -d "%")
        load=$(cat /proc/loadavg | awk "{print \$1}")
        up=$(uptime -p | sed "s/up //" | sed "s/ days\?/d/;s/ hours\?/h/;s/ minutes\?/m/;s/,//g")
        procs=$(ps aux --no-heading | wc -l)
        swap=$(free | awk "/Swap:/ {if(\$2>0) printf \"%.0f\", \$3/\$2*100; else print 0}")
        echo "${cpu}|${mem}|${disk}|${load}|${up}|${procs}|n/a|n/a|${swap}"
    ' 2>/dev/null)

    if [[ -z "${result}" ]]; then
        echo "DOWN|${host_label}|0|0|0|0|unknown|0|n/a|n/a|0"
        return
    fi

    echo "OK|${host_label}|${result}"
}

# ---------------------------------------------------------------------------
# Health scoring
# ---------------------------------------------------------------------------

compute_mood() {
    local cpu="$1" mem="$2" disk="$3"
    local score=0

    if ((cpu > CPU_CRIT)); then ((score += 3)); elif ((cpu > CPU_WARN)); then ((score += 1)); fi
    if ((mem > MEM_CRIT)); then ((score += 3)); elif ((mem > MEM_WARN)); then ((score += 1)); fi
    if ((disk > DISK_CRIT)); then ((score += 3)); elif ((disk > DISK_WARN)); then ((score += 1)); fi

    if ((score == 0)); then
        if ((cpu < 15 && mem < 30)); then
            echo "sleeping"
        else
            echo "happy"
        fi
    elif ((score <= 2)); then
        echo "okay"
    elif ((score <= 4)); then
        echo "worried"
    elif ((score <= 6)); then
        echo "stressed"
    else
        echo "dead"
    fi
}

# ---------------------------------------------------------------------------
# UI rendering
# ---------------------------------------------------------------------------

bar_graph() {
    local value="$1"
    local max_width=30
    local filled=$((value * max_width / 100))
    local empty=$((max_width - filled))

    local color="${GREEN}"
    if ((value > 90)); then color="${RED}"
    elif ((value > 70)); then color="${YELLOW}"
    fi

    printf "${color}"
    printf '%0.s█' $(seq 1 "${filled}" 2>/dev/null) || true
    printf "${DIM}"
    printf '%0.s░' $(seq 1 "${empty}" 2>/dev/null) || true
    printf "${RESET} %3d%%" "${value}"
}

render_header() {
    local width=60
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local mode="$1"

    printf "${BOLD}${CYAN}"
    printf '═%.0s' $(seq 1 "${width}")
    printf "\n"
    printf "  SERVER PET — Infrastructure Tamagotchi"
    printf "%*s" $((width - 42)) ""
    printf "\n"
    printf '═%.0s' $(seq 1 "${width}")
    printf "${RESET}\n"
    printf "  ${DIM}%s  │  mode: %s  │  refresh: %ds${RESET}\n\n" \
        "${timestamp}" "${mode}" "${REFRESH_SECONDS}"
}

render_server() {
    local status="$1" host="$2" cpu="$3" mem="$4" disk="$5"
    local load="$6" uptime_str="$7" procs="$8"
    local net_in="$9" net_out="${10}" swap="${11}"

    local mood
    if [[ "${status}" == "DOWN" ]]; then
        mood="dead"
    else
        mood=$(compute_mood "${cpu}" "${mem}" "${disk}")
    fi

    # Server name + status badge
    local badge_color="${GREEN}"
    local badge_text="ONLINE"
    if [[ "${status}" == "DOWN" ]]; then
        badge_color="${RED}"
        badge_text="DOWN"
    fi

    printf "  ${BOLD}${WHITE}┌─ %s ${badge_color}[%s]${RESET}\n" "${host}" "${badge_text}"
    printf "  ${WHITE}│${RESET}\n"

    # Creature + stats side by side
    local creature_lines
    creature_lines=$(creature_"${mood}")
    local line_num=0

    local stats_lines=()
    stats_lines+=("$(printf "${WHITE}CPU:  ${RESET}%s" "$(bar_graph "${cpu}")")")
    stats_lines+=("$(printf "${WHITE}MEM:  ${RESET}%s" "$(bar_graph "${mem}")")")
    stats_lines+=("$(printf "${WHITE}DISK: ${RESET}%s" "$(bar_graph "${disk}")")")
    stats_lines+=("$(printf "${WHITE}SWAP: ${RESET}%s" "$(bar_graph "${swap}")")")
    stats_lines+=("")
    stats_lines+=("$(printf "${DIM}Load: %-8s  Procs: %-6s${RESET}" "${load}" "${procs}")")
    stats_lines+=("$(printf "${DIM}Net:  ↓ %-12s ↑ %-12s${RESET}" "${net_in}" "${net_out}")")
    stats_lines+=("$(printf "${DIM}Up:   %s${RESET}" "${uptime_str}")")

    while IFS= read -r creature_line; do
        local stat_line=""
        if ((line_num < ${#stats_lines[@]})); then
            stat_line="${stats_lines[${line_num}]}"
        fi
        printf "  ${WHITE}│${RESET}  ${MAGENTA}%-20s${RESET}  %s\n" "${creature_line}" "${stat_line}"
        ((line_num++))
    done <<< "${creature_lines}"

    # Print remaining stats if creature shorter than stats
    while ((line_num < ${#stats_lines[@]})); do
        printf "  ${WHITE}│${RESET}  %-20s  %s\n" "" "${stats_lines[${line_num}]}"
        ((line_num++))
    done

    printf "  ${WHITE}│${RESET}\n"

    # Mood message
    local msg_array="msg_${mood}"
    local message
    message=$(pick_random "${msg_array}")
    printf "  ${WHITE}│${RESET}  ${YELLOW}💬 %s${RESET}\n" "${message}"
    printf "  ${WHITE}└──────────────────────────────────────────────────────${RESET}\n\n"
}

render_warnings() {
    local cpu="$1" mem="$2" disk="$3" host="$4"
    local has_warnings=false

    if ((cpu > CPU_CRIT)); then
        printf "  ${RED}⚠  [%s] CPU critical: %d%%${RESET}\n" "${host}" "${cpu}"
        has_warnings=true
    elif ((cpu > CPU_WARN)); then
        printf "  ${YELLOW}⚠  [%s] CPU elevated: %d%%${RESET}\n" "${host}" "${cpu}"
        has_warnings=true
    fi

    if ((mem > MEM_CRIT)); then
        printf "  ${RED}⚠  [%s] Memory critical: %d%%${RESET}\n" "${host}" "${mem}"
        has_warnings=true
    elif ((mem > MEM_WARN)); then
        printf "  ${YELLOW}⚠  [%s] Memory elevated: %d%%${RESET}\n" "${host}" "${mem}"
        has_warnings=true
    fi

    if ((disk > DISK_CRIT)); then
        printf "  ${RED}⚠  [%s] Disk critical: %d%%${RESET}\n" "${host}" "${disk}"
        has_warnings=true
    elif ((disk > DISK_WARN)); then
        printf "  ${YELLOW}⚠  [%s] Disk elevated: %d%%${RESET}\n" "${host}" "${disk}"
        has_warnings=true
    fi

    if [[ "${has_warnings}" == false ]]; then
        printf "  ${GREEN}✓  No warnings. All systems nominal.${RESET}\n"
    fi
}

render_footer() {
    printf "\n  ${DIM}[q] quit  │  [r] refresh  │  [+/-] speed${RESET}\n"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

handle_input() {
    local key
    if read -rsn1 -t 0.1 key 2>/dev/null; then
        case "${key}" in
            q|Q) cleanup; exit 0 ;;
            r|R) return 0 ;;
            +)   ((REFRESH_SECONDS > 1)) && ((REFRESH_SECONDS--)) ;;
            -)   ((REFRESH_SECONDS < 30)) && ((REFRESH_SECONDS++)) ;;
        esac
    fi
}

cleanup() {
    tput cnorm 2>/dev/null
    printf "${RESET}\n"
    echo "Server pet goes sleep. Bye."
}

show_help() {
    echo "Usage: server-pet.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help"
    echo "  -d, --demo       Force demo mode"
    echo "  -s, --server     Add server (user@host), repeatable"
    echo "  -r, --refresh    Refresh interval in seconds (default: 5)"
    echo ""
    echo "Examples:"
    echo "  ./server-pet.sh --demo"
    echo "  ./server-pet.sh -s admin@prod-1 -s admin@prod-2"
    echo "  ./server-pet.sh -s admin@prod-1 -r 10"
}

main() {
    local force_demo=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    show_help; exit 0 ;;
            -d|--demo)    force_demo=true; shift ;;
            -s|--server)  SERVERS+=("$2"); shift 2 ;;
            -r|--refresh) REFRESH_SECONDS="$2"; shift 2 ;;
            *)            echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    local mode="live"
    if [[ "${force_demo}" == true ]] || [[ ${#SERVERS[@]} -eq 0 ]]; then
        mode="demo"
    fi

    trap cleanup EXIT
    tput civis 2>/dev/null

    while true; do
        clear
        render_header "${mode}"

        if [[ "${mode}" == "demo" ]]; then
            local data
            data=$(get_demo_data)

            IFS='|' read -r status host cpu mem disk load uptime_str procs net_in net_out swap <<< "${data}"
            render_server "${status}" "${host}" "${cpu}" "${mem}" "${disk}" \
                "${load}" "${uptime_str}" "${procs}" "${net_in}" "${net_out}" "${swap}"

            printf "  ${BOLD}${WHITE}── Warnings ──${RESET}\n"
            render_warnings "${cpu}" "${mem}" "${disk}" "${host}"
        else
            for server in "${SERVERS[@]}"; do
                local data
                data=$(get_server_data "${server}")

                IFS='|' read -r status host cpu mem disk load uptime_str procs net_in net_out swap <<< "${data}"
                render_server "${status}" "${host}" "${cpu}" "${mem}" "${disk}" \
                    "${load}" "${uptime_str}" "${procs}" "${net_in}" "${net_out}" "${swap}"
            done

            printf "  ${BOLD}${WHITE}── Warnings ──${RESET}\n"
            for server in "${SERVERS[@]}"; do
                local data
                data=$(get_server_data "${server}")
                IFS='|' read -r status host cpu mem disk load uptime_str procs net_in net_out swap <<< "${data}"
                render_warnings "${cpu}" "${mem}" "${disk}" "${host}"
            done
        fi

        render_footer

        local elapsed=0
        while ((elapsed < REFRESH_SECONDS)); do
            handle_input
            sleep 0.5
            ((elapsed++)) || true
        done
    done
}

main "$@"
