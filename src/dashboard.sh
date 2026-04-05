#!/usr/bin/env bash
#
# R(5,5) Solving Dashboard — Terminal UI
# Usage: ./dashboard.sh [refresh_seconds]
#
set -uo pipefail

REFRESH="${1:-30}"
DIR="/home/antoh/Desktop/R55/results/sat/canonical_ssc/results"
LOG="/tmp/ssc_sync.log"
TOTAL=5439

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

bar() {
    local pct=$1 width=${2:-40} label=${3:-""}
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    printf "${GREEN}"
    printf '%0.s█' $(seq 1 $filled 2>/dev/null)
    printf "${DIM}"
    printf '%0.s░' $(seq 1 $empty 2>/dev/null)
    printf "${NC} %3d%% %s" "$pct" "$label"
}

sparkline() {
    local chars=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    local -a vals=("$@")
    local max=1
    for v in "${vals[@]}"; do
        (( v > max )) && max=$v
    done
    for v in "${vals[@]}"; do
        local idx=$(( v * 7 / max ))
        (( idx > 7 )) && idx=7
        printf "${CYAN}${chars[$idx]}${NC}"
    done
}

worker_count() {
    local host="$1"
    case "$host" in
        locale)
            ps aux 2>/dev/null | grep -c '[s]msg.*canonical_ssc' || echo 0
            ;;
        asus)
            ssh -o ConnectTimeout=3 whobuntu@172.19.0.2 \
                'ps aux | grep -c "[s]msg"' 2>/dev/null || echo 0
            ;;
        lenovo)
            ssh -o ConnectTimeout=3 whobuntu@172.19.0.2 \
                'ssh -o ConnectTimeout=3 whopad@192.168.1.53 \
                 "ps aux | grep -c \"[s]msg\""' 2>/dev/null || echo 0
            ;;
        server)
            ssh -o ConnectTimeout=3 hatweb-server \
                'ps aux | grep -c "[s]msg"' 2>/dev/null || echo 0
            ;;
    esac
}

while true; do
    clear

    # Gather data
    total_done=$(ls "$DIR"/ssc_*.result 2>/dev/null | wc -l)
    unsat=$(grep -rl '^UNSAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
    tout=$(grep -rl '^TIMEOUT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
    sat=$(grep -rl '^SAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
    err=$(grep -rl '^ERROR$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
    remain=$((TOTAL - total_done))
    pct=$((total_done * 100 / TOTAL))

    # Rate from last N log entries
    rates=()
    if [[ -f "$LOG" ]]; then
        prev_total=0
        while IFS= read -r line; do
            cur=$(echo "$line" | grep -oP '\d+(?=/5439)' | head -1)
            if [[ -n "$cur" && $prev_total -gt 0 ]]; then
                delta=$((cur - prev_total))
                (( delta < 0 )) && delta=0
                rates+=($((delta * 6)))  # per hour (10 min intervals)
            fi
            [[ -n "$cur" ]] && prev_total=$cur
        done < "$LOG"
    fi

    # Current rate (last interval)
    cur_rate=0
    if [[ ${#rates[@]} -gt 0 ]]; then
        cur_rate=${rates[-1]}
    fi

    # Average rate (last 6 intervals = 1 hour)
    avg_rate=0
    if [[ ${#rates[@]} -gt 0 ]]; then
        sum=0; cnt=0
        for ((i=${#rates[@]}-1; i>=0 && cnt<6; i--,cnt++)); do
            sum=$((sum + rates[i]))
        done
        (( cnt > 0 )) && avg_rate=$((sum / cnt))
    fi

    # ETA
    eta="∞"
    if [[ $avg_rate -gt 0 ]]; then
        eta_h=$((remain * 10 / avg_rate))
        eta_m=$(( (remain * 600 / avg_rate) % 60 ))
        eta="${eta_h}h${eta_m}m"
    fi

    # Workers (background check)
    w_locale=$(ps aux 2>/dev/null | grep '[s]msg' | grep -v ssh | wc -l)

    # Header
    echo -e "${BOLD}${WHITE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║              R(5,5) > 43  —  SOLVING DASHBOARD             ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S') — refresh ${REFRESH}s${NC}"
    echo ""

    # Progress bar
    echo -e "  ${BOLD}PROGRESSO GLOBALE${NC}"
    echo -n "  "
    bar $pct 50
    echo ""
    echo -e "  ${WHITE}${total_done}${NC} / ${TOTAL}  —  rimanenti: ${YELLOW}${remain}${NC}  —  ETA: ${CYAN}${eta}${NC}"
    echo ""

    # Results breakdown
    echo -e "  ${BOLD}RISULTATI${NC}"
    echo -e "  ┌─────────┬────────┬───────┐"
    printf  "  │ ${GREEN}UNSAT${NC}   │ %6d │ %s%% │\n" "$unsat" "$(LC_NUMERIC=C awk "BEGIN{printf \"%.1f\", $unsat*100/$TOTAL}")"
    printf  "  │ ${YELLOW}TIMEOUT${NC} │ %6d │ %s%% │\n" "$tout" "$(LC_NUMERIC=C awk "BEGIN{printf \"%.1f\", $tout*100/$TOTAL}")"
    printf  "  │ ${RED}SAT${NC}     │ %6d │ %s%% │\n" "$sat" "$(LC_NUMERIC=C awk "BEGIN{printf \"%.1f\", $sat*100/$TOTAL}")"
    if [[ $err -gt 0 ]]; then
        printf  "  │ ${RED}ERROR${NC}   │ %6d │ %s%% │\n" "$err" "$(LC_NUMERIC=C awk "BEGIN{printf \"%.1f\", $err*100/$TOTAL}")"
    fi
    echo -e "  └─────────┴────────┴───────┘"
    echo ""

    # Rate history (sparkline)
    echo -e "  ${BOLD}RATE${NC} (risultati/ora)"
    echo -ne "  Attuale: ${WHITE}${cur_rate}/h${NC}  Media 1h: ${WHITE}${avg_rate}/h${NC}  "
    if [[ ${#rates[@]} -gt 2 ]]; then
        # Show last 20 rates
        echo -n "Trend: "
        start=$((${#rates[@]} - 20))
        (( start < 0 )) && start=0
        sparkline "${rates[@]:$start}"
    fi
    echo ""
    echo ""

    # Workers
    echo -e "  ${BOLD}WORKER${NC}"
    echo -e "  ┌──────────────┬─────────┬──────────┬─────────┐"
    echo -e "  │ ${BOLD}Macchina${NC}     │ ${BOLD}Worker${NC}  │ ${BOLD}Timeout${NC}  │ ${BOLD}Stato${NC}   │"
    echo -e "  ├──────────────┼─────────┼──────────┼─────────┤"
    printf  "  │ Locale       │ %5d   │ 1200s    │ ${GREEN}●${NC} ON    │\n" "$w_locale"

    # Check remotes in background — use cached values if too slow
    w_asus=$(ssh -o ConnectTimeout=2 whobuntu@172.19.0.2 'ps aux | grep "[s]msg" | wc -l' 2>/dev/null || echo "?")
    if [[ "$w_asus" == "?" ]]; then
        printf "  │ ASUS         │    ?    │ 1200s    │ ${RED}●${NC} ???   │\n"
    elif [[ "$w_asus" -gt 0 ]]; then
        printf "  │ ASUS         │ %5s   │ 1200s    │ ${GREEN}●${NC} ON    │\n" "$w_asus"
    else
        printf "  │ ASUS         │     0   │ 1200s    │ ${YELLOW}●${NC} IDLE  │\n"
    fi

    w_lenovo=$(ssh -o ConnectTimeout=2 whobuntu@172.19.0.2 'ssh -o ConnectTimeout=2 whopad@192.168.1.53 "ps aux | grep \"[s]msg\" | wc -l"' 2>/dev/null || echo "?")
    if [[ "$w_lenovo" == "?" ]]; then
        printf "  │ Lenovo       │    ?    │ 1200s    │ ${RED}●${NC} ???   │\n"
    elif [[ "$w_lenovo" -gt 0 ]]; then
        printf "  │ Lenovo       │ %5s   │ 1200s    │ ${GREEN}●${NC} ON    │\n" "$w_lenovo"
    else
        printf "  │ Lenovo       │     0   │ 1200s    │ ${YELLOW}●${NC} IDLE  │\n"
    fi

    w_server=$(ssh -o ConnectTimeout=2 hatweb-server 'ps aux | grep "[s]msg" | wc -l' 2>/dev/null || echo "?")
    if [[ "$w_server" == "?" ]]; then
        printf "  │ Server       │    —    │    —     │ ${RED}●${NC} OFF   │\n"
    elif [[ "$w_server" -gt 0 ]]; then
        printf "  │ Server       │ %5s   │ 1200s    │ ${GREEN}●${NC} ON    │\n" "$w_server"
    else
        printf "  │ Server       │     0   │    —     │ ${YELLOW}●${NC} IDLE  │\n"
    fi
    echo -e "  └──────────────┴─────────┴──────────┴─────────┘"
    echo ""

    # TIMEOUT distribution (last 100 results by index)
    echo -e "  ${BOLD}MAPPA DIFFICOLTÀ${NC} ${DIM}(ultimi 500 SSC per indice — █=UNSAT ░=TIMEOUT)${NC}"
    echo -n "  "
    # Get last 500 results sorted by index
    mapcount=0
    for f in $(ls "$DIR"/ssc_*.result 2>/dev/null | sort -t_ -k2 -n | tail -500); do
        res=$(cat "$f")
        if [[ "$res" == "UNSAT" ]]; then
            echo -ne "${GREEN}█${NC}"
        elif [[ "$res" == "TIMEOUT" ]]; then
            echo -ne "${RED}░${NC}"
        else
            echo -ne "${YELLOW}?${NC}"
        fi
        mapcount=$((mapcount + 1))
        (( mapcount % 80 == 0 )) && echo -e "\n  "
    done
    echo ""
    echo ""

    # Level summary
    echo -e "  ${BOLD}LIVELLI CUBING${NC}"
    echo -e "  L1 (cutoff 50):  11 cubi   → ${GREEN}6 UNSAT${NC} + 5 hard"
    echo -e "  L2 (cutoff 70):  4483 cubi → ${GREEN}4398 UNSAT${NC} + 85 hard"
    echo -e "  L3 (cutoff 90):  5439 cubi → ${GREEN}${unsat} UNSAT${NC} + ${YELLOW}${tout} TIMEOUT${NC} + ${DIM}${remain} in corso${NC}"
    echo -e "  L4 (cutoff 110): ${DIM}in attesa completamento L3${NC}"
    echo ""

    echo -e "  ${DIM}Premi Ctrl+C per uscire${NC}"

    sleep "$REFRESH"
done
