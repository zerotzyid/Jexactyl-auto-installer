#!/usr/bin/env bash
# ==============================================================================
#  Jexactyl Auto Installer  -  one-shot Panel + Node setup
#  Copyright (c) 2026 ZeroTzyID  -  https://github.com/zerotzyid
#  All rights reserved.
# ==============================================================================

SCRIPT_VERSION="2.1.0"
BRAND="ZeroTzyID"
GITHUB="github.com/zerotzyid"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export COMPOSER_ALLOW_SUPERUSER=1

LOG="/var/log/zerotzyid-jexactyl.log"
WORK="/tmp/zerotzyid"
PANEL_DIR="/var/www/jexactyl"
DB_NAME="panel"
DB_USER="jexactyl"
CRED_FILE="/root/jexactyl-credentials.txt"

PANEL_VER="latest"
WINGS_VER="latest"
PHP_VERSION="8.4"
F2B_BACKEND="auto"
LOC_SHORT="zerotzyid"
LOC_LONG="ZeroTzyID Default Location"

MODE=""
ASSUME_YES=0
AUTO_DEF=0
AUTO=0
FORCE=0
REINSTALL=0
DNS_WAIT=120
STATUS_FILE="/var/log/zerotzyid-status.json"
REPORT="/root/zerotzyid-error.txt"
CUR_STEP_LABEL=""
REMOTE_SPECS=()
PLAIN=0
HARDEN=0
PANEL_FQDN=""
NODE_FQDN=""
EMAIL=""
ADMIN_USER=""
ADMIN_PASS=""
DB_PASS=""
PORT_RANGE=""
API_KEY=""

STEP_NOW=0
STEP_TOTAL=0
SPIN_PID=""
NODE_RESULTS=()
NODE_ERR=""
NODE_ID=""
PUB_IP=""
CUR_FQDN=""

# ------------------------------------------------------------------ colors ----
R=$'\e[0m'; B=$'\e[1m'; DIM=$'\e[2m'
PUR=$'\e[38;5;141m'; CYA=$'\e[38;5;87m'; GRN=$'\e[38;5;84m'
RED=$'\e[38;5;203m'; YEL=$'\e[38;5;221m'; GRY=$'\e[38;5;245m'

setup_ui(){
    if [ "$AUTO" = 1 ] || [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
        R=""; B=""; DIM=""; PUR=""; CYA=""; GRN=""; RED=""; YEL=""; GRY=""
    fi
}

# ------------------------------------------------------------------- UI -------
rep(){ local s="" i; for ((i=0; i<$2; i++)); do s+="$1"; done; printf '%s' "$s"; }

ok(){   printf "  ${GRN}✔${R} %s\n" "$*"; }
info(){ printf "  ${CYA}i${R} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${R} %s\n" "$*"; }
err(){  printf "  ${RED}✘${R} %s\n" "$*" >&2; }
die(){  err "$*"; write_status failed "$*"; emit_result; exit 1; }
section(){ printf "\n  ${B}${PUR}▌${R} ${B}%s${R}\n" "$1"; }

row(){ # plain_text colored_text
    local pad=$(( 60 - ${#1} ))
    [ $pad -lt 0 ] && pad=0
    printf "  ${PUR}│${R}%s%*s${PUR}│${R}\n" "$2" "$pad" ""
}

banner(){
    [ "$PLAIN" = 1 ] && return 0
    [ -t 1 ] && clear
    printf "\n  ${PUR}╭%s╮${R}\n" "$(rep '─' 60)"
    row "" ""
    row "   JEXACTYL AUTO INSTALLER" "   ${B}${CYA}JEXACTYL AUTO INSTALLER${R}"
    row "   One-shot Panel + Node setup  -  v${SCRIPT_VERSION}" "   ${GRY}One-shot Panel + Node setup  -  v${SCRIPT_VERSION}${R}"
    row "   by ${BRAND}  -  ${GITHUB}" "   ${GRY}by ${R}${B}${BRAND}${R}${GRY}  -  ${GITHUB}${R}"
    row "" ""
    printf "  ${PUR}╰%s╯${R}\n" "$(rep '─' 60)"
}

bar(){ # done total
    local w=16 f=$(( $1 * 16 / $2 ))
    printf '%s%s' "$(rep '█' "$f")" "$(rep '░' $((w - f)))"
}

spinner_start(){ # prefix label progressbar
    local pre="$1" label="$2" pb="$3"
    if [ "$AUTO" = 1 ] || [ ! -t 1 ]; then
        printf "  > %s%s ...\n" "$pre" "$label"
        return 0
    fi
    (
        f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0
        while :; do
            printf "\r\e[K  ${CYA}%s${R} ${GRY}%s${R}%s ${PUR}%s${R}" "${f[i%10]}" "$pre" "$label" "$pb"
            i=$((i + 1)); sleep 0.1
        done
    ) &
    SPIN_PID=$!
}

spinner_stop(){
    if [ -n "$SPIN_PID" ]; then
        kill "$SPIN_PID" 2>/dev/null
        wait "$SPIN_PID" 2>/dev/null
        SPIN_PID=""
    fi
    [ "$AUTO" = 1 ] || [ ! -t 1 ] || printf "\r\e[K"
}

step_log(){ # log of the current/last step only (older runs and earlier steps are ignored)
    local n
    n=$(grep -n '^=== STEP' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f1)
    if [ -n "$n" ]; then tail -n +"$n" "$LOG"; else tail -n 100 "$LOG" 2>/dev/null; fi
}

diagnose(){ # human hint based on the end of the current step's log
    local t
    t=$(step_log | tail -n 60)
    case "$t" in
        *"Job for nginx.service failed"*|*"nginx: [emerg]"*|*"nginx.service failed"*)
            echo "Nginx could not start. Usually another web server (Apache) or program already uses port 80/443, or the nginx config is invalid. Check: ss -ltnp | grep -E ':(80|443) '  and  nginx -t" ;;
        *"require a PHP version"*|*"platform_check"*)
            echo "The panel needs a newer PHP than the 'php' command uses. Run: update-alternatives --set php /usr/bin/php8.4  then start the installer again." ;;
        *"Job for mariadb.service failed"*|*"mariadb.service failed"*)
            echo "MariaDB could not start (often a failed upgrade of an older database). Check: journalctl -xeu mariadb | tail -n 30" ;;
        *"conffile prompt"*|*"end of file on stdin"*)
            echo "A package asked a config question while no terminal was attached. Run: dpkg --configure -a --force-confdef --force-confold && apt-get -f install -y  then start the installer again." ;;
        *"Could not get lock"*|*"Unable to acquire the dpkg"*|*"Waiting for cache lock"*)
            echo "Another apt/dpkg process is running. Wait a minute (or reboot the server) and run the installer again." ;;
        *"dpkg was interrupted"*)
            echo "Run: dpkg --configure -a --force-confdef --force-confold  then start the installer again." ;;
        *"Challenge failed"*|*"Timeout during connect"*|*"Connection refused"*)
            echo "Let's Encrypt could not reach this server. Check the DNS A record (DNS only, no proxy) and that port 80 is open." ;;
        *"No space left"*)
            echo "The disk is full. Free some space and run the installer again." ;;
        *"Temporary failure resolving"*|*"Could not resolve"*)
            echo "This server has no working DNS/internet. Check /etc/resolv.conf." ;;
        *) echo "" ;;
    esac
}

write_report(){ # causes clean hint
    {
        echo "ZeroTzyID installer report - $(date '+%F %T')"
        echo "Version     : ${SCRIPT_VERSION}"
        echo "OS          : ${OS_PRETTY:-unknown}"
        echo "Failed step : ${CUR_STEP_LABEL}"
        echo
        echo "[Cause]"
        echo "$1"
        echo
        echo "[Fix]"
        echo "${3:-no automatic suggestion}"
        echo
        echo "[Log tail]"
        echo "$2"
    } > "$REPORT" 2>/dev/null
}

fail_tail(){
    local causes clean hint
    causes=$(step_log | tail -n 60 | grep -E '^(E:|dpkg: error|COMMAND FAILED)|rror:|Challenge failed|Could not|denied|failed' | grep -v '^NOTICE' | awk '!seen[$0]++' | tail -n 6)
    clean=$(step_log | tail -n 40 | grep -vE '^(NOTICE:|Selecting previously|Preparing to unpack|Unpacking|Get:|Hit:|Reading |Building |\(Reading database|Setting up|Creating config|Processing triggers)' | grep -v '^[[:space:]]*$' | tail -n 10)
    hint=$(diagnose)
    write_report "$causes" "$clean" "$hint"
    printf "\n  ${RED}${B}Why it failed${R}\n"
    [ -n "$causes" ] && printf '%s\n' "$causes" | sed 's/^/    /'
    [ -n "$hint" ] && printf "\n  ${YEL}Fix:${R} %s\n" "$hint"
    printf "\n  ${GRY}----- Copy this text when asking for help -----${R}\n"
    cat "$REPORT" 2>/dev/null
    printf "  ${GRY}----- End (saved to %s, full log: %s) -----${R}\n\n" "$REPORT" "$LOG"
}

run_step(){ # label function [args]
    local label="$1" pre="" pb="" t0=$SECONDS rc
    shift
    CUR_STEP_LABEL="$label"
    STEP_NOW=$((STEP_NOW + 1))
    if [ "$STEP_TOTAL" -gt 0 ]; then
        pre="[$STEP_NOW/$STEP_TOTAL] "
        pb="$(bar $((STEP_NOW - 1)) "$STEP_TOTAL")"
    fi
    echo "=== STEP ${pre}${label} ($(date '+%F %T'))" >> "$LOG"
    write_status running
    spinner_start "$pre" "$label" "$pb"
    "$@" >> "$LOG" 2>&1 < /dev/null
    rc=$?
    spinner_stop
    if [ $rc -eq 0 ]; then
        printf "  ${GRN}✔${R} ${GRY}%s${R}%s ${DIM}(%ss)${R}\n" "$pre" "$label" "$((SECONDS - t0))"
    else
        printf "  ${RED}✘${R} ${GRY}%s${R}%s\n" "$pre" "$label"
        fail_tail
        write_status failed "Step failed: ${label}"
    fi
    return $rc
}

run_flow(){ # "Label|function" ...
    local items=("$@") it
    STEP_NOW=0
    STEP_TOTAL=${#items[@]}
    for it in "${items[@]}"; do
        run_step "${it%%|*}" "${it##*|}" || { STEP_TOTAL=0; return 1; }
    done
    STEP_TOTAL=0
    return 0
}

req(){ "$@"; local rc=$?; [ $rc -ne 0 ] && echo "COMMAND FAILED (exit $rc): $*"; return $rc; }

cleanup(){
    [ -n "$SPIN_PID" ] && kill "$SPIN_PID" 2>/dev/null
    printf '\e[?25h'
}
trap cleanup EXIT
trap 'printf "\n"; warn "Cancelled by user."; exit 130' INT TERM

# --------------------------------------------------------------- input --------
ask(){ # var "Label" [default] [validator]
    local var="$1" label="$2" def="${3:-}" validator="${4:-}" val
    val="${!var:-}"
    if [ -n "$val" ]; then
        if [ -z "$validator" ] || "$validator" "$val"; then
            ok "$label: ${B}${val}${R}"; return 0
        fi
        warn "Invalid value for $label: $val"
    fi
    if [ "$AUTO_DEF" = 1 ] && [ -n "$def" ] && { [ -z "$validator" ] || "$validator" "$def"; }; then
        printf -v "$var" '%s' "$def"
        ok "$label: ${B}${def}${R} ${GRY}(auto)${R}"
        return 0
    fi
    [ "$AUTO" = 1 ] && die "Missing or invalid value for: ${label} (pass it as a CLI flag)"
    while true; do
        if [ -n "$def" ]; then
            printf "  ${PUR}❯${R} %s ${GRY}[%s]${R}: " "$label" "$def"
        else
            printf "  ${PUR}❯${R} %s: " "$label"
        fi
        IFS= read -r val < /dev/tty || die "No terminal available for input. Use CLI flags (see --help)."
        val="${val:-$def}"
        if [ -z "$val" ]; then warn "This value is required."; continue; fi
        if [ -n "$validator" ] && ! "$validator" "$val"; then warn "Invalid format, please try again."; continue; fi
        printf -v "$var" '%s' "$val"
        return 0
    done
}

ask_secret(){ # var "Label" [validator]
    local var="$1" label="$2" validator="${3:-}" val
    val="${!var:-}"
    [ -n "$val" ] && return 0
    [ "$AUTO" = 1 ] && die "Missing required secret: ${label} (pass it as a CLI flag)"
    while true; do
        printf "  ${PUR}❯${R} %s: " "$label"
        IFS= read -rs val < /dev/tty || die "No terminal available for input."
        printf '\n'
        [ -z "$val" ] && continue
        if [ -n "$validator" ] && ! "$validator" "$val"; then warn "Invalid format, please try again."; continue; fi
        break
    done
    printf -v "$var" '%s' "$val"
}

confirm(){ # "Question" [y|n]
    local q="$1" d="${2:-y}" a hint
    if [ "$ASSUME_YES" = 1 ]; then [ "$d" = y ]; return; fi
    [ "$d" = y ] && hint="Y/n" || hint="y/N"
    printf "  ${YEL}?${R} %s ${GRY}[%s]${R} " "$q" "$hint"
    IFS= read -r a < /dev/tty || a=""
    a="${a:-$d}"
    case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

menu(){ # title items... -> MENU_SEL (0-based)
    local title="$1"; shift
    local -a items=("$@")
    local n=${#items[@]} sel=0 i key rest first=1
    printf '\e[?25l'
    printf "\n  ${B}%s${R}  ${GRY}(arrows to move, Enter to select, or press a number)${R}\n\n" "$title"
    while true; do
        [ $first -eq 0 ] && printf '\e[%dA' "$n"
        first=0
        for ((i = 0; i < n; i++)); do
            if [ $i -eq $sel ]; then
                printf "\r\e[K  ${PUR}❯${R} ${B}${CYA}%s${R}\n" "${items[i]}"
            else
                printf "\r\e[K    ${GRY}%s${R}\n" "${items[i]}"
            fi
        done
        IFS= read -rsn1 key < /dev/tty || { printf '\e[?25h'; die "No terminal available."; }
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 0.1 rest < /dev/tty
                case "$rest" in
                    '[A') sel=$(( (sel - 1 + n) % n )) ;;
                    '[B') sel=$(( (sel + 1) % n )) ;;
                esac ;;
            '') break ;;
            k) sel=$(( (sel - 1 + n) % n )) ;;
            j) sel=$(( (sel + 1) % n )) ;;
            [0-9])
                if [ "$key" = 0 ]; then
                    if [[ "${items[n-1]}" == 0* ]]; then sel=$((n - 1)); break; fi
                elif [ "$key" -le "$n" ]; then
                    sel=$((key - 1)); break
                fi ;;
        esac
    done
    printf '\e[?25h'
    MENU_SEL=$sel
}

# ----------------------------------------------------------- validators -------
is_fqdn(){ local re='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; [[ "$1" =~ $re ]]; }
is_email(){ local re='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; [[ "$1" =~ $re ]]; }
is_user(){ local re='^[a-z0-9][a-z0-9_.-]{1,30}[a-z0-9]$'; [[ "$1" =~ $re ]]; }
is_apikey(){ local re='^ptla_[A-Za-z0-9]{20,}$'; [[ "$1" =~ $re ]]; }
is_ports(){
    local re='^[0-9]{2,5}(-[0-9]{2,5})?$' s e
    [[ "$1" =~ $re ]] || return 1
    s="${1%-*}"; e="${1#*-}"
    [ "$s" -ge 1024 ] && [ "$e" -le 65535 ] && [ "$s" -le "$e" ] && [ $((e - s)) -lt 1000 ]
}

default_email(){ local d="${1#*.}"; [[ "$d" == *.* ]] || d="$1"; echo "admin@${d}"; }
version_ge(){ [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
rand_str(){ tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-24}"; }
resolve_ip(){ dig +short A "$1" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1; }
public_ip(){
    local ip
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com -4 2>/dev/null | tail -n1)
    [ -z "$ip" ] && ip=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null)
    echo "$ip"
}
sql(){ mysql -N -B "$DB_NAME" -e "$1"; }

dns_check(){ # fqdn expected_ip label
    local fqdn="$1" want="$2" label="$3" got a waited=0
    while true; do
        got=$(resolve_ip "$fqdn")
        if [ -n "$got" ] && [ "$got" = "$want" ]; then ok "DNS ${label}: ${fqdn} -> ${got}"; return 0; fi
        warn "DNS ${label}: ${fqdn} resolves to '${got:-nothing}', expected ${want}"
        info "Create an A record for ${fqdn} pointing to ${want} (Cloudflare: DNS only / grey cloud)."
        [ "$PLAIN" = 1 ] && printf 'ZT_ERROR|dns|%s|%s|%s\n' "$fqdn" "${got:-none}" "$want"
        if [ "$ASSUME_YES" = 1 ] || [ "$AUTO" = 1 ]; then
            waited=$((waited + 10))
            [ "$waited" -gt "$DNS_WAIT" ] && return 1
            sleep 10
            continue
        fi
        printf "  ${YEL}?${R} [R]etry, [C]ontinue anyway, [Q]uit: "
        IFS= read -r a < /dev/tty || a="q"
        case "${a,,}" in c) return 0 ;; q) exit 1 ;; esac
    done
}

# ------------------------------------------------------------ preflight -------
os_check(){
    [ -r /etc/os-release ] || die "Cannot detect operating system."
    lsb_dist="$(. /etc/os-release && echo "$ID")"
    dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
    OS_PRETTY="$(. /etc/os-release && echo "$PRETTY_NAME")"
    case "$lsb_dist" in
        ubuntu)
            version_ge "$dist_version" "20.04" || die "Unsupported Ubuntu ${dist_version}. Ubuntu 20.04 or newer is required."
            case "$dist_version" in
                20.04|22.04|24.04) ;;
                *) warn "Ubuntu ${dist_version} is not tested with this script. Continuing at your own risk." ;;
            esac
            if version_ge "$dist_version" "22.04"; then F2B_BACKEND="systemd"; fi ;;
        debian)
            case "$dist_version" in
                11|12) F2B_BACKEND="systemd" ;;
                *) die "Unsupported Debian ${dist_version}. Debian 11 or 12 is required." ;;
            esac ;;
        *) die "Unsupported OS: ${OS_PRETTY}. Supported: Ubuntu 20.04/22.04/24.04+ and Debian 11/12." ;;
    esac
}

preflight(){
    section "System check"
    [ "$EUID" -eq 0 ] || die "Please run as root (sudo -i)."
    mkdir -p "$WORK"; : >> "$LOG"
    os_check
    ok "Operating system: ${OS_PRETTY}"
    case "$(uname -m)" in
        x86_64) ARCH_WINGS="amd64" ;;
        aarch64|arm64) ARCH_WINGS="arm64" ;;
        *) die "Unsupported architecture $(uname -m). Use x86_64 or arm64." ;;
    esac
    ok "Architecture: $(uname -m)"
    [ -d /run/systemd/system ] || die "systemd is required."
    ok "Resources: $(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo) MB RAM, $(df -Pm / | awk 'NR==2 {print $4}') MB free disk"
}

apt_prepare(){
    cat > /etc/apt/apt.conf.d/99zerotzyid <<'APTCONF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
DPkg::Lock::Timeout "300";
APT::Get::Assume-Yes "true";
APTCONF
    export UCF_FORCE_CONFFOLD=1
}

recover_dpkg(){
    dpkg --configure -a --force-confdef --force-confold
    apt-get -f install -y
}

step_base_tools(){
    apt_prepare
    recover_dpkg || true
    req apt-get update -y || return 1
    req apt-get install -y software-properties-common curl wget dnsutils virt-what ca-certificates \
        gnupg lsb-release jq acl sudo unzip tar || return 1
    if [ "$lsb_dist" = ubuntu ]; then add-apt-repository -y universe || true; fi
    return 0
}

virt_check(){
    local v kern
    v=$(echo $(virt-what 2>/dev/null))
    case "$v" in
        "") ok "Virtualization: bare metal" ;;
        kvm|vmware|hyperv|"openvz lxc"|"xen xen-hvm"|"xen xen-hvm aws") ok "Virtualization: ${v}" ;;
        *)
            warn "Unsupported virtualization detected: ${v}. Docker may not work on this server."
            confirm "Proceed anyway?" n || exit 5 ;;
    esac
    kern="$(uname -r)"
    case "$kern" in
        *xxxx*) die "OVH custom kernel detected. Reinstall with a distribution kernel first." ;;
        *stab*2.6*) die "OpenVZ 6 detected. Docker will not work here." ;;
        *pve*) warn "Proxmox LXC kernel detected. Proceeding at your own risk." ;;
        *gcp*) warn "Google Cloud detected: use a static IP and allow ports 80, 443, 8080, 2022 in the GCP firewall." ;;
        *) ok "Kernel: ${kern}" ;;
    esac
}

# --------------------------------------------------------- panel steps --------
detect_php_version(){
    local url tmp req v
    if [ "$PANEL_VER" = latest ]; then
        url="https://github.com/jexactyl/jexactyl/releases/latest/download/panel.tar.gz"
    else
        url="https://github.com/jexactyl/jexactyl/releases/download/${PANEL_VER}/panel.tar.gz"
    fi
    tmp="$WORK/probe"; mkdir -p "$tmp"
    if curl -fsSL --max-time 120 -o "$tmp/panel.tar.gz" "$url" && tar -xzf "$tmp/panel.tar.gz" -C "$tmp" composer.json 2>/dev/null; then
        req=$(jq -r '.require.php // empty' "$tmp/composer.json" 2>/dev/null)
        v=$(printf '%s' "$req" | grep -oE '8\.[0-9]+' | sort -V | head -n1)
        if [ -n "$v" ]; then
            PHP_VERSION="$v"
            echo "Panel requires PHP '${req}', using PHP ${PHP_VERSION}."
        else
            echo "Could not read the PHP requirement, using PHP ${PHP_VERSION}."
        fi
    else
        echo "Could not download the panel to check its PHP requirement, using PHP ${PHP_VERSION}."
    fi
    rm -rf "$tmp"
    return 0
}

step_repos(){
    detect_php_version
    req apt-get update -y || return 1
    req apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release wget sudo || return 1
    if [ "$lsb_dist" = ubuntu ]; then
        req env LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || return 1
        add-apt-repository -y ppa:redislabs/redis || echo "redislabs PPA unavailable, using distribution redis."
    else
        req curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/deb.sury.org-php.gpg || return 1
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi
    if dpkg -s mariadb-server >/dev/null 2>&1; then
        echo "MariaDB is already installed, keeping the current repository."
    else
        curl -fsSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11" \
            || echo "MariaDB repo setup failed, using distribution MariaDB."
    fi
    req apt-get update -y
}

free_ports(){
    local svc
    for svc in apache2 httpd; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "Stopping and disabling ${svc} (it uses port 80/443, nginx is needed instead)."
            systemctl disable --now "$svc" 2>/dev/null || systemctl stop "$svc" 2>/dev/null
        fi
    done
    echo "Listeners on 80/443:"
    ss -ltnp 2>/dev/null | grep -E ':(80|443)\s' || echo "  none"
    return 0
}

nginx_diag(){
    echo "--- nginx diagnostics ---"
    nginx -t 2>&1
    ss -ltnp 2>/dev/null | grep -E ':(80|443)\s'
    journalctl -u nginx -n 15 --no-pager 2>&1
}

step_packages(){
    free_ports
    local pk=("php${PHP_VERSION}" php${PHP_VERSION}-{cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
        mariadb-server nginx tar unzip git redis-server cron acl certbot jq ufw fail2ban dnsutils)
    if ! req apt-get install -y "${pk[@]}"; then
        echo "Package install failed, running automatic recovery and retrying once..."
        recover_dpkg
        req apt-get install -y "${pk[@]}" || return 1
    fi
    if [ "$F2B_BACKEND" = systemd ]; then apt-get install -y python3-systemd || true; fi
    update-alternatives --set php "/usr/bin/php${PHP_VERSION}" 2>/dev/null || true
    update-alternatives --set phar "/usr/bin/phar${PHP_VERSION}" 2>/dev/null || true
    if [ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)" != "$PHP_VERSION" ]; then
        echo "The 'php' command is not PHP ${PHP_VERSION} (found: $(php -v 2>/dev/null | head -n1))."
        return 1
    fi
    systemctl enable --now redis-server "php${PHP_VERSION}-fpm" cron || return 1
    systemctl enable --now mariadb || { journalctl -u mariadb -n 25 --no-pager; return 1; }
    free_ports
    systemctl enable nginx
    systemctl restart nginx || { nginx_diag; echo "nginx could not start yet, it will be configured in a later step."; }
    return 0
}

step_composer(){
    req curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php || return 1
    req php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || return 1
    rm -f /tmp/composer-setup.php
    return 0
}

step_database(){
    req mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
}

step_download(){
    local url
    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR" || return 1
    if [ "$PANEL_VER" = latest ]; then
        url="https://github.com/jexactyl/jexactyl/releases/latest/download/panel.tar.gz"
    else
        url="https://github.com/jexactyl/jexactyl/releases/download/${PANEL_VER}/panel.tar.gz"
    fi
    req curl -fsSLo panel.tar.gz "$url" || return 1
    req tar -xzf panel.tar.gz || return 1
    rm -f panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    return 0
}

step_composer_install(){
    cd "$PANEL_DIR" || return 1
    req composer install --no-dev --optimize-autoloader --no-interaction
}

step_configure_panel(){
    local tz
    cd "$PANEL_DIR" || return 1
    tz="$(timedatectl show -p Timezone --value 2>/dev/null)"
    php -r 'exit(in_array($argv[1] ?? "", DateTimeZone::listIdentifiers()) ? 0 : 1);' "$tz" || tz="UTC"
    cp .env.example .env
    req php artisan key:generate --force || return 1
    req php artisan p:environment:setup -n --author="$EMAIL" --url="https://${PANEL_FQDN}" --timezone="$tz" \
        --cache=redis --session=database --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 || return 1
    req php artisan p:environment:database --host=127.0.0.1 --port=3306 --database="$DB_NAME" \
        --username="$DB_USER" --password="$DB_PASS" || return 1
    req php artisan migrate --seed --force || return 1
    req php artisan p:user:make --email="$EMAIL" --username="$ADMIN_USER" --name-first="Admin" --name-last="Panel" \
        --password="$ADMIN_PASS" --admin=1
}

step_queue_cron(){
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1") | crontab -
    cat > /etc/systemd/system/pteroq.service <<EOF
# Jexactyl Queue Worker File
[Unit]
Description=Jexactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    chown -R www-data:www-data "$PANEL_DIR"
    systemctl daemon-reload
    systemctl enable --now pteroq.service
}

step_ssl_panel(){
    free_ports
    req certbot certonly --standalone --non-interactive --agree-tos --no-eff-email -m "$EMAIL" \
        -d "$PANEL_FQDN" --keep-until-expiring \
        --pre-hook "systemctl stop nginx 2>/dev/null || true" \
        --post-hook "systemctl start nginx 2>/dev/null || true" || return 1
    systemctl start nginx 2>/dev/null
    [ -f "/etc/letsencrypt/live/${PANEL_FQDN}/fullchain.pem" ] || { echo "Certificate file not found."; return 1; }
    systemctl enable --now certbot.timer 2>/dev/null
    return 0
}

step_nginx(){
    rm -f /etc/nginx/sites-enabled/default
    cat > /etc/nginx/sites-available/jexactyl.conf <<'NGINX'
server {
    listen 80;
    server_name __FQDN__;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name __FQDN__;

    root /var/www/jexactyl/public;
    index index.php;

    access_log /var/log/nginx/jexactyl.app-access.log;
    error_log  /var/log/nginx/jexactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/__FQDN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__FQDN__/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php__PHP__-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX
    sed -i "s|__FQDN__|${PANEL_FQDN}|g; s|__PHP__|${PHP_VERSION}|g" /etc/nginx/sites-available/jexactyl.conf
    ln -sf /etc/nginx/sites-available/jexactyl.conf /etc/nginx/sites-enabled/jexactyl.conf
    req nginx -t || return 1
    free_ports
    systemctl restart nginx || { nginx_diag; return 1; }
}

step_firewall(){
    local sshp
    sshp=$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')
    sshp="${sshp:-22}"
    ufw allow "${sshp}/tcp"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable || echo "ufw could not be enabled on this system, continuing."
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Ban hosts for ten hours:
bantime = 36000
banaction = iptables-multiport
backend = ${F2B_BACKEND}

[sshd]
enabled = true
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban || echo "fail2ban could not be started, continuing."
    return 0
}

step_harden(){
    curl -fsSL https://raw.githubusercontent.com/Whonix/security-misc/master/etc/modprobe.d/30_security-misc.conf >> /etc/modprobe.d/30_security-misc.conf || echo "modprobe hardening source unavailable, skipped."
    curl -fsSL https://raw.githubusercontent.com/Whonix/security-misc/master/etc/sysctl.d/30_security-misc.conf >> /etc/sysctl.d/30_security-misc.conf || echo "sysctl hardening source unavailable, skipped."
    sed -i 's/kernel.yama.ptrace_scope=2/kernel.yama.ptrace_scope=3/g' /etc/sysctl.d/30_security-misc.conf 2>/dev/null
    return 0
}

step_finalize(){
    chown -R www-data:www-data "$PANEL_DIR"
    systemctl restart pteroq 2>/dev/null
    return 0
}

# ------------------------------------------------ node provisioning (panel) ---
write_php_helpers(){
    mkdir -p "$WORK"
    cat > "$WORK/check_node.php" <<'PHP'
<?php
require '/var/www/jexactyl/vendor/autoload.php';
$app = require '/var/www/jexactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$ns = class_exists('Everest\\Models\\Node') ? 'Everest' : 'Pterodactyl';
try {
    $nodeClass = $ns . '\\Models\\Node';
    $repoClass = $ns . '\\Repositories\\Wings\\DaemonConfigurationRepository';
    $node = $nodeClass::findOrFail((int) $argv[1]);
    $info = app($repoClass)->setNode($node)->getSystemInformation();
    echo 'wings ' . ($info['version'] ?? 'online');
    exit(0);
} catch (Throwable $e) {
    echo get_class($e) . ': ' . substr($e->getMessage(), 0, 160);
    exit(1);
}
PHP
    cat > "$WORK/node_config.php" <<'PHP'
<?php
require '/var/www/jexactyl/vendor/autoload.php';
$app = require '/var/www/jexactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$ns = class_exists('Everest\\Models\\Node') ? 'Everest' : 'Pterodactyl';
$nodeClass = $ns . '\\Models\\Node';
echo $nodeClass::findOrFail((int) $argv[1])->getYamlConfiguration();
PHP
    cat > "$WORK/create_node.php" <<'PHP'
<?php
require '/var/www/jexactyl/vendor/autoload.php';
$app = require '/var/www/jexactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$ns = class_exists('Everest\\Models\\Node') ? 'Everest' : 'Pterodactyl';
$serviceClass = $ns . '\\Services\\Nodes\\NodeCreationService';
$data = [
    'name' => getenv('ZT_NAME'),
    'description' => 'Auto-created by ZeroTzyID installer',
    'fqdn' => getenv('ZT_FQDN'),
    'scheme' => 'https',
    'behind_proxy' => false,
    'public' => true,
    'maintenance_mode' => false,
    'memory' => (int) getenv('ZT_MEM'),
    'memory_overallocate' => 0,
    'disk' => (int) getenv('ZT_DISK'),
    'disk_overallocate' => 0,
    'upload_size' => 100,
    'daemon_base' => '/var/lib/pterodactyl/volumes',
    'listen_port_http' => 8080,
    'listen_port_sftp' => 2022,
    'public_port_http' => 8080,
    'public_port_sftp' => 2022,
    'daemonListen' => 8080,
    'daemonSFTP' => 2022,
    'daemonBase' => '/var/lib/pterodactyl/volumes',
];
if (getenv('ZT_LOC') !== false && getenv('ZT_LOC') !== '') {
    $data['location_id'] = (int) getenv('ZT_LOC');
}
$node = app($serviceClass)->handle($data);
echo $node->id;
PHP
}

res_script(){
    cat <<'EOS'
mem=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
disk=$(df -Pm / | awk 'NR==2 {print $4}')
echo "$mem $disk"
EOS
}

calc_res(){ # "mem disk" -> NODE_MEM NODE_DISK (90%)
    local m d
    read -r m d <<< "$1"
    NODE_MEM=$(( m * 90 / 100 )); NODE_DISK=$(( d * 90 / 100 ))
    [ "$NODE_MEM" -lt 256 ] && NODE_MEM=$m
    [ "$NODE_DISK" -lt 1024 ] && NODE_DISK=$d
    return 0
}

create_allocations(){ # node_id ip range
    local nid="$1" ip="$2" rng="$3" s e p vals=""
    s="${rng%-*}"; e="${rng#*-}"
    for ((p = s; p <= e; p++)); do vals+="(${nid},'${ip}',${p},NOW(),NOW()),"; done
    sql "INSERT IGNORE INTO allocations (node_id, ip, port, created_at, updated_at) VALUES ${vals%,};"
}

fetch_node_config(){ # node_id
    local out
    out=$(cd "$PANEL_DIR" && php artisan p:node:configuration "$1" 2>/dev/null)
    if ! printf '%s' "$out" | grep -q 'token_id'; then
        out=$(cd "$PANEL_DIR" && php "$WORK/node_config.php" "$1" 2>/dev/null)
    fi
    printf '%s' "$out" | grep -q 'token_id' || return 1
    printf '%s\n' "$out"
}

provision_node(){ # fqdn ip  (uses NODE_MEM / NODE_DISK) -> NODE_ID + config file
    local fqdn="$1" ip="$2" loc_id="" name
    local -a loc_args=()
    name="ZT-${fqdn%%.*}"
    cd "$PANEL_DIR" || return 1
    write_php_helpers
    if php artisan list --raw 2>/dev/null | grep -q '^p:location:make'; then
        loc_id=$(sql "SELECT id FROM locations WHERE short='${LOC_SHORT}' LIMIT 1")
        if [ -z "$loc_id" ]; then
            req php artisan p:location:make --no-interaction --short="$LOC_SHORT" --long="$LOC_LONG" || return 1
            loc_id=$(sql "SELECT id FROM locations WHERE short='${LOC_SHORT}' LIMIT 1")
        fi
        [ -n "$loc_id" ] || { echo "Location could not be created."; return 1; }
        loc_args=(--locationId="$loc_id")
    else
        echo "This panel version has no locations, skipping location setup."
    fi
    NODE_ID=$(sql "SELECT id FROM nodes WHERE fqdn='${fqdn}' ORDER BY id DESC LIMIT 1")
    if [ -z "$NODE_ID" ]; then
        php artisan p:node:make --no-interaction --name="$name" --description="Auto-created by ZeroTzyID installer" \
            "${loc_args[@]}" --fqdn="$fqdn" --public=1 --scheme=https --proxy=0 --maintenance=0 \
            --maxMemory="$NODE_MEM" --overallocateMemory=0 --maxDisk="$NODE_DISK" --overallocateDisk=0 \
            --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
        NODE_ID=$(sql "SELECT id FROM nodes WHERE fqdn='${fqdn}' ORDER BY id DESC LIMIT 1")
        if [ -z "$NODE_ID" ]; then
            echo "p:node:make failed, using direct creation fallback."
            ZT_NAME="$name" ZT_LOC="$loc_id" ZT_FQDN="$fqdn" ZT_MEM="$NODE_MEM" ZT_DISK="$NODE_DISK" \
                php "$WORK/create_node.php"
            NODE_ID=$(sql "SELECT id FROM nodes WHERE fqdn='${fqdn}' ORDER BY id DESC LIMIT 1")
        fi
    else
        echo "Node for ${fqdn} already exists (ID ${NODE_ID}), reusing it."
    fi
    [ -n "$NODE_ID" ] || { echo "Node could not be created."; return 1; }
    create_allocations "$NODE_ID" "$ip" "$PORT_RANGE" || return 1
    fetch_node_config "$NODE_ID" > "$WORK/config-${NODE_ID}.yml" || { echo "Could not generate node configuration."; return 1; }
    echo "Node ${NODE_ID} created for ${fqdn} (${NODE_MEM} MB RAM, ${NODE_DISK} MB disk, ports ${PORT_RANGE})."
}

wait_green(){ # node_id
    local i out
    for i in $(seq 1 45); do
        if out=$(cd "$PANEL_DIR" && php "$WORK/check_node.php" "$1" 2>&1); then
            echo "Node $1 is ONLINE (${out})."; return 0
        fi
        echo "attempt ${i}/45: ${out}"
        sleep 4
    done
    return 1
}

node_result(){ # fqdn id status detail
    NODE_RESULTS+=("$1|$2|$3|$4")
}

# ----------------------------------------------------- wings install script --
emit_wings_script(){
    cat <<'WSCRIPT'
#!/usr/bin/env bash
# ZeroTzyID - Wings installer (Docker + SSL + Wings binary + systemd)
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
NODE_FQDN="$1"; EMAIL="$2"; WINGS_VER="${3:-latest}"
case "$(uname -m)" in
    x86_64) WARCH=amd64 ;;
    aarch64|arm64) WARCH=arm64 ;;
    *) echo "Unsupported architecture"; exit 1 ;;
esac
command -v apt-get >/dev/null || { echo "Only Debian/Ubuntu nodes are supported"; exit 1; }
apt-get update -y || exit 1
apt-get install -y curl tar unzip ca-certificates certbot ufw jq dnsutils || exit 1

if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | CHANNEL=stable bash || exit 1
fi
systemctl enable --now docker || exit 1

if [ ! -f "/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem" ]; then
    certbot certonly --standalone --non-interactive --agree-tos --no-eff-email -m "$EMAIL" \
        -d "$NODE_FQDN" --keep-until-expiring \
        --pre-hook "systemctl stop nginx 2>/dev/null || true" \
        --post-hook "systemctl start nginx 2>/dev/null || true" \
        || { echo "Certbot failed. Make sure ${NODE_FQDN} points to this server and port 80 is free."; exit 1; }
    systemctl start nginx 2>/dev/null || true
fi

mkdir -p /etc/pterodactyl /var/lib/pterodactyl/volumes /var/log/pterodactyl
if [ "$WINGS_VER" = latest ]; then
    URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WARCH}"
else
    URL="https://github.com/pterodactyl/wings/releases/download/${WINGS_VER}/wings_linux_${WARCH}"
fi
curl -fsSL -o /usr/local/bin/wings "$URL" || exit 1
chmod u+x /usr/local/bin/wings

cat > /etc/systemd/system/wings.service <<'UNIT'
[Unit]
Description=Jexactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable wings

if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 8080/tcp
    ufw allow 2022/tcp
fi
echo "Wings installed."
WSCRIPT
}

wings_install_local(){
    mkdir -p "$WORK"
    emit_wings_script > "$WORK/wings_setup.sh"
    req bash "$WORK/wings_setup.sh" "$CUR_FQDN" "$EMAIL" "$WINGS_VER"
}

# ---------------------------------------------- full / local node steps -------
step_node_create_local(){
    calc_res "$(res_script | bash)"
    provision_node "$CUR_FQDN" "$PUB_IP"
}

step_wings_install_local(){
    wings_install_local || return 1
    install -d -m 700 /etc/pterodactyl
    install -m 600 "$WORK/config-${NODE_ID}.yml" /etc/pterodactyl/config.yml
}

step_node_start_local(){
    systemctl restart wings
    sleep 3
    if wait_green "$NODE_ID"; then
        node_result "$CUR_FQDN" "$NODE_ID" ok "online"
        return 0
    fi
    journalctl -u wings -n 40 --no-pager
    NODE_ERR="Wings did not respond to the panel (check ports 8080/2022 and the SSL certificate)."
    return 1
}

# ------------------------------------------------------- remote node (SSH) ----
rsh(){
    local -a opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=30 -p "$CUR_SSH_PORT")
    if [ -n "$CUR_SSH_PASS" ]; then
        SSHPASS="$CUR_SSH_PASS" sshpass -e ssh "${opts[@]}" "${CUR_SSH_USER}@${CUR_SSH_HOST}" "$@"
    else
        ssh -i "$CUR_SSH_KEY" -o BatchMode=yes "${opts[@]}" "${CUR_SSH_USER}@${CUR_SSH_HOST}" "$@"
    fi
}

collect_remote_node(){ # fills CUR_* ; returns 1 on failure
    local rip rres
    [ "${1:-}" = preset ] || { CUR_FQDN=""; CUR_SSH_HOST=""; CUR_SSH_PORT=""; CUR_SSH_USER=""; CUR_SSH_PASS=""; CUR_SSH_KEY=""; }
    ask CUR_FQDN "Node FQDN (e.g. node2.example.com)" "" is_fqdn
    ask CUR_SSH_HOST "SSH host/IP of that server" "$CUR_FQDN"
    ask CUR_SSH_PORT "SSH port" "22"
    ask CUR_SSH_USER "SSH user (must be root)" "root"
    if [ -z "$CUR_SSH_PASS" ] && [ -z "$CUR_SSH_KEY" ]; then
        menu "SSH authentication" "1  Password" "2  Private key file"
        if [ "$MENU_SEL" -eq 0 ]; then
            ask_secret CUR_SSH_PASS "SSH password"
        else
            ask CUR_SSH_KEY "Path to private key" "/root/.ssh/id_rsa"
        fi
    fi
    if [ -n "$CUR_SSH_PASS" ]; then
        command -v sshpass >/dev/null || { info "Installing sshpass..."; apt-get install -y sshpass >> "$LOG" 2>&1; }
    else
        [ -r "$CUR_SSH_KEY" ] || { err "Key file not readable: $CUR_SSH_KEY"; return 1; }
    fi
    info "Connecting to ${CUR_SSH_USER}@${CUR_SSH_HOST}:${CUR_SSH_PORT} ..."
    [ "$(rsh 'id -u' 2>/dev/null)" = "0" ] || { err "SSH login failed or user is not root."; return 1; }
    rsh 'command -v apt-get' >/dev/null 2>&1 || { err "Remote server must be Debian/Ubuntu."; return 1; }
    ok "SSH connection OK"
    rip=$(rsh 'curl -4 -fsS --max-time 8 https://api.ipify.org || dig +short myip.opendns.com @resolver1.opendns.com -4' 2>/dev/null | tail -n1)
    [ -n "$rip" ] || { err "Could not detect the public IP of the remote server."; return 1; }
    CUR_IP="$rip"
    dns_check "$CUR_FQDN" "$CUR_IP" "node" || return 1
    rres=$(res_script | rsh 'bash -s' 2>/dev/null)
    [ -n "$rres" ] || { err "Could not read remote resources."; return 1; }
    CUR_RES="$rres"
    return 0
}

step_node_create_remote(){
    calc_res "$CUR_RES"
    provision_node "$CUR_FQDN" "$CUR_IP"
}

step_wings_install_remote(){
    emit_wings_script > "$WORK/wings_setup.sh"
    req rsh "bash -s -- '${CUR_FQDN}' '${EMAIL}' '${WINGS_VER}'" < "$WORK/wings_setup.sh"
}

step_remote_config(){
    req rsh "mkdir -p /etc/pterodactyl && umask 077 && cat > /etc/pterodactyl/config.yml" < "$WORK/config-${NODE_ID}.yml"
}

step_node_start_remote(){
    rsh "systemctl restart wings"
    sleep 3
    if wait_green "$NODE_ID"; then
        node_result "$CUR_FQDN" "$NODE_ID" ok "online"
        return 0
    fi
    rsh "journalctl -u wings -n 40 --no-pager"
    NODE_ERR="Panel could not reach Wings on ${CUR_FQDN}:8080 (check firewall/provider security group)."
    return 1
}

run_node_flow(){ # flow items...
    run_flow "$@" && return 0
    [[ "${NODE_RESULTS[*]}" == *"${CUR_FQDN}|"* ]] || node_result "$CUR_FQDN" "${NODE_ID:--}" fail "${NODE_ERR:-setup step failed, see ${LOG}}"
    return 1
}

deploy_remote_nodes(){ # interactive loop
    local more=1
    while [ "$more" -eq 1 ]; do
        section "Remote node"
        if collect_remote_node; then
            NODE_ID=""; NODE_ERR=""
            run_node_flow \
                "Creating node, location & allocations in panel|step_node_create_remote" \
                "Installing Docker, Wings & SSL on ${CUR_FQDN}|step_wings_install_remote" \
                "Uploading node configuration|step_remote_config" \
                "Starting Wings & waiting for green node|step_node_start_remote"
        else
            warn "Skipping this node."
        fi
        if confirm "Add another remote node?" n; then more=1; else more=0; fi
    done
}

# --------------------------------------------- node only (existing panel) -----
api(){ # method path [json]
    local m="$1" p="$2" d="${3:-}"
    local -a extra=()
    [ -n "$d" ] && extra=(-d "$d")
    curl -sS -g -X "$m" "https://${PANEL_FQDN}/api/application${p}" \
        -H "Authorization: Bearer ${API_KEY}" -H "Accept: Application/vnd.pterodactyl.v1+json" \
        -H "Content-Type: application/json" "${extra[@]}"
}

step_api_register(){
    local loc="" existing body
    api GET /nodes | jq -e '.data' >/dev/null || { echo "API key rejected by the panel (or panel unreachable)."; return 1; }
    if api GET /locations 2>/dev/null | jq -e '.data' >/dev/null 2>&1; then
        loc=$(api GET /locations | jq -r '.data[0].attributes.id // empty')
        if [ -z "$loc" ]; then
            loc=$(api POST /locations "{\"short\":\"${LOC_SHORT}\",\"long\":\"${LOC_LONG}\"}" | jq -r '.attributes.id // empty')
        fi
    fi
    calc_res "$(res_script | bash)"
    existing=$(api GET "/nodes?filter[fqdn]=${CUR_FQDN}" | jq -r '.data[0].attributes.id // empty')
    if [ -n "$existing" ]; then
        NODE_ID="$existing"; echo "Node already exists (ID ${NODE_ID}), reusing."
    else
        body=$(jq -n --arg name "ZT-${CUR_FQDN%%.*}" --arg fqdn "$CUR_FQDN" --argjson loc "${loc:-null}" \
            --argjson mem "$NODE_MEM" --argjson disk "$NODE_DISK" \
            '{name:$name,description:"Auto-created by ZeroTzyID installer",fqdn:$fqdn,scheme:"https",behind_proxy:false,public:true,memory:$mem,memory_overallocate:0,disk:$disk,disk_overallocate:0,daemon_base:"/var/lib/pterodactyl/volumes",upload_size:100,listen_port_http:8080,listen_port_sftp:2022,public_port_http:8080,public_port_sftp:2022,daemon_sftp:2022,daemon_listen:8080}
             | if $loc != null then .location_id=$loc else . end')
        NODE_ID=$(api POST /nodes "$body" | jq -r '.attributes.id // empty')
    fi
    [ -n "$NODE_ID" ] || { echo "Node creation through the API failed."; return 1; }
    api POST "/nodes/${NODE_ID}/allocations" "{\"ip\":\"${PUB_IP}\",\"ports\":[\"${PORT_RANGE}\"]}"
    echo "Node ${NODE_ID} registered."
}

step_api_configure(){
    req /usr/local/bin/wings configure --panel-url "https://${PANEL_FQDN}" --token "$API_KEY" --node "$NODE_ID" --override
}

step_api_start(){
    local i code
    systemctl restart wings
    for i in $(seq 1 30); do
        code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://${CUR_FQDN}:8080/" 2>/dev/null)
        if systemctl is-active --quiet wings && [ "$code" != "000" ]; then
            echo "Wings is running and answering over HTTPS (HTTP ${code})."
            node_result "$CUR_FQDN" "$NODE_ID" ok "online"
            return 0
        fi
        sleep 4
    done
    journalctl -u wings -n 40 --no-pager
    NODE_ERR="Wings is not answering on https://${CUR_FQDN}:8080."
    return 1
}

# ------------------------------------------------ bot / automation helpers ----
write_status(){ # state [detail]
    [ "$1" = failed ] && [ "$AUTO" = 1 ] && printf 'ZT_ERROR|failed|%s|%s\n' "$CUR_STEP_LABEL" "${2:-}"
    command -v jq >/dev/null 2>&1 || return 0
    jq -n --arg state "$1" --arg detail "${2:-}" --arg step "$CUR_STEP_LABEL" \
        --argjson n "${STEP_NOW:-0}" --argjson t "${STEP_TOTAL:-0}" --arg ts "$(date -Is)" \
        '{state:$state,detail:$detail,step:$step,step_now:$n,step_total:$t,updated:$ts}' \
        > "${STATUS_FILE}.tmp" 2>/dev/null && mv -f "${STATUS_FILE}.tmp" "$STATUS_FILE" && chmod 600 "$STATUS_FILE"
    return 0
}

write_final(){
    command -v jq >/dev/null 2>&1 || return 0
    local nodes="[]" objs="" r f i st d state="done"
    for r in "${NODE_RESULTS[@]}"; do
        IFS='|' read -r f i st d <<< "$r"
        [ "$st" = ok ] || state="done_with_errors"
        objs+="$(jq -nc --arg f "$f" --arg i "$i" --arg s "$st" --arg d "$d" '{fqdn:$f,id:$i,status:$s,detail:$d}')"$'\n'
    done
    [ -n "$objs" ] && nodes=$(printf '%s' "$objs" | jq -sc '.')
    jq -n --arg state "$state" --arg ts "$(date -Is)" --arg url "${PANEL_FQDN:+https://$PANEL_FQDN}" \
        --arg email "$EMAIL" --arg user "$ADMIN_USER" --arg pass "$ADMIN_PASS" --argjson nodes "$nodes" \
        '{state:$state,step:"Finished",updated:$ts,panel:{url:$url,email:$email,username:$user,password:$pass},nodes:$nodes}' \
        > "${STATUS_FILE}.tmp" 2>/dev/null && mv -f "${STATUS_FILE}.tmp" "$STATUS_FILE" && chmod 600 "$STATUS_FILE"
    return 0
}

emit_result(){ # one machine-readable line for bots
    if [ "$AUTO" = 1 ] && [ -f "$STATUS_FILE" ]; then
        echo "ZT_RESULT $(tr -d '\n' < "$STATUS_FILE")"
    fi
    return 0
}

existing_check(){
    local found=""
    [ -f /var/www/pterodactyl/.env ] && found="/var/www/pterodactyl"
    systemctl list-unit-files 2>/dev/null | grep -q '^pteroq.service' && found="${found:+$found, }pteroq.service"
    [ -z "$found" ] && return 0
    warn "Existing panel files found: ${found}. Installing here may overwrite them."
    [ "$FORCE" = 1 ] && return 0
    if [ "$AUTO" = 1 ] || [ "$ASSUME_YES" = 1 ]; then
        die "Existing panel found (${found}). Use a clean server or add --force."
    fi
    confirm "Continue anyway?" n || exit 0
}

pick_db_name(){
    local n
    command -v mysql >/dev/null 2>&1 || return 0
    n=$(mysql -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'" 2>/dev/null)
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
        DB_NAME="panel_$(rand_str 5 | tr 'A-Z' 'a-z')"
        info "Database 'panel' already contains data, using ${DB_NAME} instead."
    fi
    return 0
}

deploy_remote_auto(){ # specs: fqdn,host,port,user,password[,keyfile]
    local spec
    for spec in "${REMOTE_SPECS[@]}"; do
        section "Remote node"
        CUR_FQDN=""; CUR_SSH_HOST=""; CUR_SSH_PORT=""; CUR_SSH_USER=""; CUR_SSH_PASS=""; CUR_SSH_KEY=""
        IFS=',' read -r CUR_FQDN CUR_SSH_HOST CUR_SSH_PORT CUR_SSH_USER CUR_SSH_PASS CUR_SSH_KEY <<< "$spec"
        CUR_SSH_HOST="${CUR_SSH_HOST:-$CUR_FQDN}"; CUR_SSH_PORT="${CUR_SSH_PORT:-22}"; CUR_SSH_USER="${CUR_SSH_USER:-root}"
        NODE_ID=""; NODE_ERR=""
        if collect_remote_node preset; then
            run_node_flow \
                "Creating node, location & allocations in panel|step_node_create_remote" \
                "Installing Docker, Wings & SSL on ${CUR_FQDN}|step_wings_install_remote" \
                "Uploading node configuration|step_remote_config" \
                "Starting Wings & waiting for green node|step_node_start_remote"
        else
            node_result "${CUR_FQDN:-unknown}" "-" fail "SSH/DNS check failed for ${CUR_SSH_HOST}"
        fi
    done
}

# ----------------------------------------------------------- summary ---------
save_credentials(){
    umask 077
    cat > "$CRED_FILE" <<EOF
# Jexactyl credentials - generated by ${BRAND} installer ($(date '+%F %T'))
Panel URL      : https://${PANEL_FQDN}
Admin email    : ${EMAIL}
Admin username : ${ADMIN_USER}
Admin password : ${ADMIN_PASS}
Database       : ${DB_NAME} / user ${DB_USER} / password ${DB_PASS}
EOF
}

summary(){
    local r fqdn id st det
    if [ "$PLAIN" = 1 ]; then
        [ -n "$ADMIN_PASS" ] && [ -f "$CRED_FILE" ] && printf 'ZT_PANEL|https://%s|%s|%s|%s\n' "$PANEL_FQDN" "$EMAIL" "$ADMIN_USER" "$ADMIN_PASS"
        for r in "${NODE_RESULTS[@]}"; do printf 'ZT_NODE|%s\n' "$r"; done
        printf 'ZT_DONE\n'
        rm -f /etc/apt/apt.conf.d/99zerotzyid
        write_final
        emit_result
        return 0
    fi
    section "Done"
    printf "\n  ${PUR}╭%s╮${R}\n" "$(rep '─' 60)"
    if [ -n "$ADMIN_PASS" ] && [ -n "$PANEL_FQDN" ] && [ -f "$CRED_FILE" ]; then
        printf "  ${PUR}│${R} ${B}Panel${R}\n"
        printf "  ${PUR}│${R}   URL       ${CYA}https://%s${R}\n" "$PANEL_FQDN"
        printf "  ${PUR}│${R}   Email     %s\n" "$EMAIL"
        printf "  ${PUR}│${R}   Username  %s\n" "$ADMIN_USER"
        printf "  ${PUR}│${R}   Password  ${YEL}%s${R}\n" "$ADMIN_PASS"
        printf "  ${PUR}│${R}\n"
    fi
    if [ ${#NODE_RESULTS[@]} -gt 0 ]; then
        printf "  ${PUR}│${R} ${B}Nodes${R}\n"
        for r in "${NODE_RESULTS[@]}"; do
            IFS='|' read -r fqdn id st det <<< "$r"
            if [ "$st" = ok ]; then
                printf "  ${PUR}│${R}   ${GRN}●${R} %s ${GRY}(ID %s)${R}  ${GRN}green / ready to use${R}\n" "$fqdn" "$id"
            else
                printf "  ${PUR}│${R}   ${RED}●${R} %s ${GRY}(ID %s)${R}  ${RED}not ready${R}\n" "$fqdn" "$id"
                printf "  ${PUR}│${R}       ${DIM}%s${R}\n" "$det"
            fi
        done
        printf "  ${PUR}│${R}\n"
    fi
    [ -f "$CRED_FILE" ] && printf "  ${PUR}│${R} ${GRY}Credentials saved to ${CRED_FILE}${R}\n"
    printf "  ${PUR}│${R} ${GRY}Install log: ${LOG}${R}\n"
    printf "  ${PUR}│${R} ${GRY}Need 3306 open for Database Hosts? Run: ufw allow 3306/tcp${R}\n"
    printf "  ${PUR}╰%s╯${R}\n\n" "$(rep '─' 60)"
    printf "  ${GRY}Made by ${R}${B}${BRAND}${R}${GRY} - ${GITHUB}${R}\n\n"
    copy_block
    rm -f /etc/apt/apt.conf.d/99zerotzyid
    write_final
    emit_result
}

copy_block(){
    local r f i st d
    printf "  ${GRY}----- Salin teks di bawah -----${R}\n"
    if [ -n "$ADMIN_PASS" ] && [ -f "$CRED_FILE" ]; then
        echo "Panel    : https://${PANEL_FQDN}"
        echo "Email    : ${EMAIL}"
        echo "Username : ${ADMIN_USER}"
        echo "Password : ${ADMIN_PASS}"
    fi
    for r in "${NODE_RESULTS[@]}"; do
        IFS='|' read -r f i st d <<< "$r"
        if [ "$st" = ok ]; then echo "Node     : ${f} (ID ${i}) - hijau, siap dipakai"
        else echo "Node     : ${f} - GAGAL: ${d}"; fi
    done
    printf "  ${GRY}----- Selesai -----${R}\n\n"
}

# ------------------------------------------------------------ modes ----------
panel_exists(){ [ -f "$PANEL_DIR/.env" ]; }

collect_panel_inputs(){
    section "Panel details"
    ask PANEL_FQDN "Panel FQDN (panel.example.com)" "" is_fqdn
    ask EMAIL "Admin email, e.g. yourname@gmail.com (also used for Let's Encrypt)" "$([ "$AUTO_DEF" = 1 ] && default_email "$PANEL_FQDN")" is_email
    ask ADMIN_USER "Admin username" "admin" is_user
    [ -z "$ADMIN_PASS" ] && ADMIN_PASS="$(rand_str 20)"
    DB_PASS="$(rand_str 32)"
    PUB_IP="$(public_ip)"
    [ -n "$PUB_IP" ] || die "Could not detect this server's public IP."
    dns_check "$PANEL_FQDN" "$PUB_IP" "panel" || die "DNS check failed for $PANEL_FQDN."
}

collect_node_inputs(){ # local node
    section "Node details"
    ask NODE_FQDN "Node FQDN (can equal panel FQDN)" "${PANEL_FQDN:-}" is_fqdn
    ask PORT_RANGE "Allocation port range" "25565-25600" is_ports
    dns_check "$NODE_FQDN" "$PUB_IP" "node" || die "DNS check failed for $NODE_FQDN."
    CUR_FQDN="$NODE_FQDN"
}

panel_flow_items(){
    FLOW_PANEL=(
        "Adding PHP / MariaDB repositories|step_repos"
        "Installing PHP, MariaDB, Nginx & Redis|step_packages"
        "Installing Composer|step_composer"
        "Creating database|step_database"
        "Downloading Jexactyl panel|step_download"
        "Installing panel dependencies|step_composer_install"
        "Configuring panel & creating admin user|step_configure_panel"
        "Setting up queue worker & cron|step_queue_cron"
        "Issuing SSL certificate for panel|step_ssl_panel"
        "Configuring Nginx|step_nginx"
        "Configuring firewall & Fail2Ban|step_firewall"
    )
    if [ "$HARDEN" = 1 ]; then FLOW_PANEL+=("Applying kernel hardening|step_harden"); fi
}

plan_card(){
    printf "\n  ${PUR}╭%s╮${R}\n" "$(rep '─' 60)"
    printf "  ${PUR}│${R} ${B}Install plan${R}\n"
    printf "  ${PUR}│${R}   Panel   ${CYA}https://%s${R}\n" "$PANEL_FQDN"
    printf "  ${PUR}│${R}   Node    ${CYA}https://%s:8080${R}\n" "$NODE_FQDN"
    printf "  ${PUR}│${R}   Admin   %s (%s)\n" "$ADMIN_USER" "$EMAIL"
    printf "  ${PUR}│${R}   Ports   %s\n" "$PORT_RANGE"
    printf "  ${PUR}│${R}   Server  %s\n" "$PUB_IP"
    printf "  ${PUR}╰%s╯${R}\n\n" "$(rep '─' 60)"
    confirm "Start installation?" y || exit 0
}

mode_local_node(){ # panel already installed on this server: only create + set up the node
    section "Panel already installed"
    PANEL_FQDN=$(grep -E '^APP_URL=' "$PANEL_DIR/.env" 2>/dev/null | sed -E 's#^APP_URL=https?://##' | tr -d '"/ ')
    DB_NAME=$(grep -E '^DB_DATABASE=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
    DB_NAME="${DB_NAME:-panel}"
    info "Panel found: ${PANEL_FQDN:-unknown}. Only the node will be created now."
    ask EMAIL "Email for Let's Encrypt (e.g. yourname@gmail.com)" "$([ "$AUTO_DEF" = 1 ] && default_email "${PANEL_FQDN:-panel.local}")" is_email
    PUB_IP="$(public_ip)"
    [ -n "$PUB_IP" ] || die "Could not detect this server's public IP."
    collect_node_inputs
    section "Installing"
    NODE_ID=""; NODE_ERR=""
    run_node_flow \
        "Creating node & allocations|step_node_create_local" \
        "Installing Docker, Wings & node SSL|step_wings_install_local" \
        "Starting Wings & waiting for green node|step_node_start_local"
    run_flow "Finalizing permissions|step_finalize"
    if [ ${#REMOTE_SPECS[@]} -gt 0 ]; then
        deploy_remote_auto
        run_flow "Finalizing permissions|step_finalize"
    fi
    summary
}

mode_full(){
    local decided=0
    if panel_exists; then
        if [ "$REINSTALL" = 1 ]; then
            decided=1
        elif [ "$ASSUME_YES" = 1 ]; then
            info "Jexactyl is already installed here: only the node will be created (add --reinstall to delete and install fresh)."
            mode_local_node
            return
        else
            section "Existing panel found"
            warn "Jexactyl is already installed in ${PANEL_DIR}."
            menu "What do you want to do?" \
                "1  Delete it, then install again" \
                "2  Keep the panel, only create and set up the node" \
                "3  Cancel (do not install)"
            case "$MENU_SEL" in
                0) decided=1 ;;
                1) mode_local_node; return ;;
                *) info "Installation cancelled. Nothing was changed."; exit 0 ;;
            esac
        fi
    fi
    reinstall_guard both "$decided"
    existing_check
    collect_panel_inputs
    collect_node_inputs
    pick_db_name
    plan_card
    section "Installing"
    panel_flow_items
    run_flow "${FLOW_PANEL[@]}" || die "Panel installation failed. See ${LOG}"
    save_credentials
    NODE_ID=""; NODE_ERR=""
    run_node_flow \
        "Creating location, node & allocations|step_node_create_local" \
        "Installing Docker, Wings & node SSL|step_wings_install_local" \
        "Starting Wings & waiting for green node|step_node_start_local"
    run_flow "Finalizing permissions|step_finalize"
    if [ ${#REMOTE_SPECS[@]} -gt 0 ]; then
        deploy_remote_auto
        run_flow "Finalizing permissions|step_finalize"
    elif confirm "Also add remote node(s) over SSH?" n; then
        deploy_remote_nodes
        run_flow "Finalizing permissions|step_finalize"
    fi
    summary
}

mode_panel_only(){
    reinstall_guard panel
    existing_check
    collect_panel_inputs
    pick_db_name
    section "Installing"
    panel_flow_items
    FLOW_PANEL+=("Finalizing permissions|step_finalize")
    run_flow "${FLOW_PANEL[@]}" || die "Panel installation failed. See ${LOG}"
    save_credentials
    summary
}

mode_node_api(){
    reinstall_guard wings
    section "Existing panel"
    ask PANEL_FQDN "Panel FQDN (already installed)" "" is_fqdn
    info "Create an Application API key in the panel: Admin > Application API (Read & Write for Nodes, Locations, Allocations)."
    ask_secret API_KEY "Application API key (ptla_...)" is_apikey
    ask EMAIL "Email for Let's Encrypt (e.g. yourname@gmail.com)" "$([ "$AUTO_DEF" = 1 ] && default_email "$PANEL_FQDN")" is_email
    section "Node details"
    ask NODE_FQDN "Node FQDN (this server)" "" is_fqdn
    ask PORT_RANGE "Allocation port range" "25565-25600" is_ports
    PUB_IP="$(public_ip)"
    [ -n "$PUB_IP" ] || die "Could not detect this server's public IP."
    dns_check "$NODE_FQDN" "$PUB_IP" "node" || die "DNS check failed for $NODE_FQDN."
    CUR_FQDN="$NODE_FQDN"
    section "Installing"
    NODE_ID=""; NODE_ERR=""
    run_node_flow \
        "Installing Docker, Wings & node SSL|wings_install_local" \
        "Registering node in your panel (API)|step_api_register" \
        "Configuring Wings automatically|step_api_configure" \
        "Starting Wings & verifying|step_api_start"
    summary
}

mode_remote(){
    panel_exists || die "No panel found in ${PANEL_DIR}. Run this on the panel server."
    [ -n "$PANEL_FQDN" ] || PANEL_FQDN=$(grep -E '^APP_URL=' "$PANEL_DIR/.env" 2>/dev/null | sed -E 's#^APP_URL=https?://##' | tr -d '"/ ')
    ask EMAIL "Email for Let's Encrypt (e.g. yourname@gmail.com)" "$([ "$AUTO_DEF" = 1 ] && default_email "${PANEL_FQDN:-panel.local}")" is_email
    ask PORT_RANGE "Allocation port range" "25565-25600" is_ports
    if [ ${#REMOTE_SPECS[@]} -gt 0 ]; then deploy_remote_auto; else deploy_remote_nodes; fi
    run_flow "Finalizing permissions|step_finalize"
    summary
}

# ------------------------------------------------------ delete / clear --------
wings_exists(){ [ -x /usr/local/bin/wings ] || [ -f /etc/systemd/system/wings.service ] || [ -f /etc/pterodactyl/config.yml ]; }

env_val(){ grep -E "^$1=" "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'; }

existing_kind(){ # what the action needs: panel|wings|both -> prints what really exists: panel|wings|both|none
    local hp=0 hw=0
    case "$1" in panel|both) panel_exists && hp=1 ;; esac
    case "$1" in wings|both) wings_exists && hw=1 ;; esac
    if [ $hp = 1 ] && [ $hw = 1 ]; then echo both
    elif [ $hp = 1 ]; then echo panel
    elif [ $hw = 1 ]; then echo wings
    else echo none
    fi
}

wipe_plan(){ # panel|wings|both
    local kind="$1" n
    section "What will be deleted"
    if [ "$kind" = panel ] || [ "$kind" = both ]; then
        warn "Panel: ${PANEL_DIR} (all files), database '$(env_val DB_DATABASE)', queue worker (pteroq), cron entry, Nginx site"
    fi
    if [ "$kind" = wings ] || [ "$kind" = both ]; then
        n=$(find /var/lib/pterodactyl/volumes -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        warn "Wings: service, /usr/local/bin/wings, /etc/pterodactyl, game server containers"
        warn "Wings: ALL server data in /var/lib/pterodactyl (${n} server folder(s), including backups)"
    fi
    info "Kept: Docker, PHP, MariaDB, Nginx packages and SSL certificates (so a new install can reuse them)."
}

wipe_confirm(){
    if [ "$ASSUME_YES" = 1 ]; then return 0; fi
    warn "This cannot be undone."
    confirm "Delete now?" n
}

step_wipe_wings(){
    local ids
    echo "Stopping Wings..."
    systemctl stop wings 2>/dev/null
    systemctl disable wings 2>/dev/null
    if command -v docker >/dev/null 2>&1; then
        systemctl is-active --quiet docker || systemctl start docker 2>/dev/null
        if docker info >/dev/null 2>&1; then
            ids=$( { docker ps -aq --filter "label=Service=Pterodactyl"; docker ps -aq --filter "network=pterodactyl_nw"; } 2>/dev/null | sort -u)
            # shellcheck disable=SC2086
            [ -n "$ids" ] && docker rm -f $ids
            docker network rm pterodactyl_nw 2>/dev/null
        else
            echo "Docker is not responding, game server containers were not removed."
        fi
    fi
    awk '{print $2}' /proc/mounts | grep -E '^/var/lib/pterodactyl' | sort -r | while read -r m; do umount -l "$m" 2>/dev/null; done
    rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/log/pterodactyl /tmp/pterodactyl /run/wings /var/run/wings
    rm -f /usr/local/bin/wings /etc/systemd/system/wings.service
    systemctl daemon-reload
    systemctl reset-failed wings 2>/dev/null
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw --force delete allow 8080/tcp 2>/dev/null
        ufw --force delete allow 2022/tcp 2>/dev/null
    fi
    return 0
}

step_wipe_panel(){
    local db user
    db="$(env_val DB_DATABASE)"; user="$(env_val DB_USERNAME)"
    db="${db:-$DB_NAME}"; user="${user:-$DB_USER}"
    [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || db=""
    [[ "$user" =~ ^[A-Za-z0-9_.-]+$ ]] || user=""
    case "$db" in mysql|information_schema|performance_schema|sys) db="" ;; esac
    case "$user" in root|mysql|mariadb.sys|PUBLIC) user="" ;; esac

    echo "Stopping queue worker and removing cron..."
    systemctl stop pteroq 2>/dev/null
    systemctl disable pteroq 2>/dev/null
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload
    systemctl reset-failed pteroq 2>/dev/null
    crontab -l 2>/dev/null | grep -vF "${PANEL_DIR}/artisan schedule:run" | crontab -

    echo "Removing Nginx site..."
    rm -f /etc/nginx/sites-enabled/jexactyl.conf /etc/nginx/sites-available/jexactyl.conf
    if command -v nginx >/dev/null 2>&1 && nginx -t 2>/dev/null; then systemctl reload nginx 2>/dev/null; fi

    if command -v mysql >/dev/null 2>&1; then
        systemctl is-active --quiet mariadb || systemctl start mariadb 2>/dev/null
        [ -n "$db" ] && mysql -e "DROP DATABASE IF EXISTS \`${db}\`;"
        [ -n "$user" ] && mysql -e "DROP USER IF EXISTS '${user}'@'127.0.0.1'; FLUSH PRIVILEGES;"
    fi

    cd / || true
    case "$PANEL_DIR" in ""|/|/var|/var/www) echo "Unsafe panel directory '${PANEL_DIR}', not deleting."; return 1 ;; esac
    rm -rf "$PANEL_DIR"
    rm -f "$CRED_FILE"
    return 0
}

run_wipe(){ # panel|wings|both
    local kind="$1" items=()
    section "Deleting"
    if [ "$kind" = wings ] || [ "$kind" = both ]; then items+=("Removing Wings, game server containers & data|step_wipe_wings"); fi
    if [ "$kind" = panel ] || [ "$kind" = both ]; then items+=("Removing panel, database, queue worker & Nginx site|step_wipe_panel"); fi
    run_flow "${items[@]}" || die "Cleanup failed. See ${LOG}"
    ok "Cleanup finished."
}

do_wipe(){ # panel|wings|both (only what exists)
    wipe_plan "$1"
    wipe_confirm || { info "Cancelled. Nothing was deleted."; exit 0; }
    run_wipe "$1"
}

reinstall_guard(){ # needed: panel|wings|both  [decided=1 when the user already chose "delete"]
    local need="$1" decided="${2:-0}" k name
    k="$(existing_kind "$need")"
    [ "$k" = none ] && return 0
    case "$k" in panel) name="Panel" ;; wings) name="Wings" ;; *) name="Panel and Wings" ;; esac
    [ "$REINSTALL" = 1 ] && decided=1
    if [ "$decided" != 1 ]; then
        section "Existing installation found"
        warn "${name} already installed on this server."
        if [ "$ASSUME_YES" = 1 ]; then
            die "${name} already installed. Add --reinstall to delete it first and install again."
        fi
        menu "What do you want to do?" \
            "1  Delete it, then install again" \
            "2  Cancel (do not install)"
        if [ "$MENU_SEL" -ne 0 ]; then info "Installation cancelled. Nothing was changed."; exit 0; fi
    fi
    do_wipe "$k"
}

mode_delete(){ # panel|wings|both
    local want="$1" k label
    case "$want" in panel) label="panel" ;; wings) label="Wings" ;; *) label="panel or Wings" ;; esac
    k="$(existing_kind "$want")"
    if [ "$k" = none ]; then
        info "Nothing to delete: no ${label} found on this server."
        write_status deleted "nothing found"; emit_result
        return 0
    fi
    do_wipe "$k"
    write_status deleted "Deleted: ${k}"
    emit_result
    case "$k" in
        both)  ok "Panel and Wings deleted. The server is clean." ;;
        panel) ok "Panel deleted." ;;
        wings) ok "Wings deleted." ;;
    esac
    if [ "$k" = wings ] || [ "$k" = both ]; then
        info "If this node is still listed in a panel, delete it there (Admin > Nodes)."
    fi
    printf "  ${GRY}----- Selesai -----${R}\n\n"
}

mode_delete_panel(){ mode_delete panel; }
mode_delete_wings(){ mode_delete wings; }
mode_delete_all(){   mode_delete both; }

# -------------------------------------------------- upgrades & extras --------
mode_upgrade_panel(){
    panel_exists || die "No panel found in ${PANEL_DIR}."
    cd "$PANEL_DIR" && php artisan p:upgrade
    chown -R www-data:www-data "$PANEL_DIR"
    ok "Panel upgraded."
}

mode_upgrade_wings(){
    local url
    if [ "$WINGS_VER" = latest ]; then
        url="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_WINGS}"
    else
        url="https://github.com/pterodactyl/wings/releases/download/${WINGS_VER}/wings_linux_${ARCH_WINGS}"
    fi
    curl -fsSL -o /usr/local/bin/wings "$url" || die "Download failed."
    chmod u+x /usr/local/bin/wings
    systemctl restart wings
    ok "Wings upgraded to ${WINGS_VER}."
}

mode_phpmyadmin(){
    local ip blow
    panel_exists || die "Install the panel first."
    apt-get install -y phpmyadmin fail2ban >> "$LOG" 2>&1 || die "phpMyAdmin install failed. See ${LOG}"
    ln -sf /usr/share/phpmyadmin "$PANEL_DIR/public/phpmyadmin"
    ip="$(public_ip)"
    blow="$(rand_str 34)"
    cat > /etc/phpmyadmin/config.inc.php <<EOF
<?php
/* Servers configuration */
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['verbose'] = 'MariaDB';
\$cfg['Servers'][\$i]['host'] = '${ip}';
\$cfg['Servers'][\$i]['port'] = '3306';
\$cfg['Servers'][\$i]['socket'] = '';
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['user'] = 'root';
\$cfg['Servers'][\$i]['password'] = '';
\$cfg['Servers'][\$i]['ssl'] = true;
\$cfg['ForceSSL'] = true;
\$cfg['blowfish_secret'] = '${blow}';
\$cfg['DefaultLang'] = 'en';
\$cfg['ServerDefault'] = 1;
\$cfg['UploadDir'] = '/var/lib/phpmyadmin/upload';
\$cfg['SaveDir'] = '/var/lib/phpmyadmin/save';
\$cfg['AuthLog'] = 'syslog';
EOF
    chmod 755 /etc/phpmyadmin; chmod 644 /etc/phpmyadmin/config.inc.php
    chown -R www-data:www-data "$PANEL_DIR" /var/lib/phpmyadmin/temp 2>/dev/null
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
banaction = iptables-multiport
backend = ${F2B_BACKEND}
[sshd]
enabled = true
[phpmyadmin-syslog]
enabled = true
maxentry = 15
EOF
    systemctl restart fail2ban
    ok "phpMyAdmin installed: https://<your-panel-domain>/phpmyadmin"
}

mode_mariadb_reset(){
    curl -sSL https://raw.githubusercontent.com/tommytran732/MariaDB-Root-Password-Reset/master/mariadb-104.sh | bash
}

mode_db_host_reset(){
    local ip pw
    ip="$(public_ip)"; pw="$(rand_str 32)"
    mysql mysql -e "SET old_passwords=0; SET PASSWORD FOR 'admin'@'${ip}' = PASSWORD('${pw}'); FLUSH PRIVILEGES;" || die "Reset failed."
    ok "New database host: ${ip}:3306  user: admin  password: ${pw}"
}

usage(){
    cat <<EOF
Jexactyl Auto Installer v${SCRIPT_VERSION} - by ${BRAND} (${GITHUB})

Usage: bash install.sh [options]

  --full               Install panel + node on this server (one-shot)
  --panel-only         Install the panel only
  --panel FQDN         Panel domain (panel.example.com)
  --node FQDN          Node domain (node.example.com)
  --email EMAIL        Admin email (also used for Let's Encrypt)
  --admin-user NAME    Admin username (default: admin)
  --admin-pass PASS    Admin password (default: random)
  --ports RANGE        Allocation port range (default: 25565-25600)
  --node-only          Install Wings only and auto-register to an existing panel
  --panel FQDN         (with --node-only: the existing panel) 
  --api-key KEY        Application API key (ptla_...) for --node-only
  --plain              Machine-readable output (for bots), implies -y
  --harden             Apply extra kernel hardening (optional)
  --remote SPEC        Remote node over SSH, repeatable:  fqdn,host,port,user,password[,keyfile]
  --auto, --bot        No prompts, no colors, status in ${STATUS_FILE} (for Telegram bots / scripts)
  --force              Continue even if another panel is already on this server
  --reinstall          If a panel / Wings already exists: delete it first, then install (no prompt)
  --delete-panel       Delete the panel (files, database, queue worker, cron, Nginx site)
  --delete-wings       Delete Wings (service, binary, config, game server containers & data)
  --delete-all, --clear  Delete the panel and Wings (clean server)
  --dns-wait SEC       Seconds to wait for DNS to propagate in --auto mode (default 120)
  -y, --yes            Accept defaults, no confirmation prompts
  -h, --help           Show this help

Fully automatic example:
  bash install.sh --full --panel panel.example.com --node node.example.com --email you@example.com -y

Telegram bot / script (no terminal needed):
  bash install.sh --auto --full --panel panel.example.com --node node.example.com
  progress : cat ${STATUS_FILE}
  result   : last output line starting with ZT_RESULT (JSON, contains panel login + node status)

Delete / clear:
  bash install.sh --delete-panel          # panel only
  bash install.sh --delete-wings          # Wings only
  bash install.sh --delete-all -y         # both, no confirmation
  bash install.sh --auto --full --panel panel.example.com --node node.example.com --reinstall

Minimal (email defaults to admin@<domain>):
  bash install.sh --full --panel panel.example.com --node node.example.com -y
EOF
}

parse_args(){
    while [ $# -gt 0 ]; do
        case "$1" in
            --full) MODE=1 ;;
            --panel-only) MODE=2 ;;
            --panel) PANEL_FQDN="${2:-}"; shift ;;
            --node) NODE_FQDN="${2:-}"; shift ;;
            --email) EMAIL="${2:-}"; shift ;;
            --admin-user) ADMIN_USER="${2:-}"; shift ;;
            --admin-pass) ADMIN_PASS="${2:-}"; shift ;;
            --ports) PORT_RANGE="${2:-}"; shift ;;
            --node-only) MODE=3 ;;
            --api-key) API_KEY="${2:-}"; shift ;;
            --plain) PLAIN=1; AUTO=1; AUTO_DEF=1; ASSUME_YES=1 ;;
            --harden) HARDEN=1 ;;
            --auto|--bot) AUTO=1 ;;
            --force) FORCE=1 ;;
            --reinstall) REINSTALL=1 ;;
            --delete-panel) MODE=10 ;;
            --delete-wings) MODE=11 ;;
            --delete-all|--clear) MODE=12 ;;
            --remote) REMOTE_SPECS+=("${2:-}"); shift ;;
            --dns-wait) DNS_WAIT="${2:-120}"; shift ;;
            -y|--yes) ASSUME_YES=1; AUTO_DEF=1 ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

main(){
    parse_args "$@"
    if [ "$AUTO" != 1 ] && [ ! -t 0 ] && ! { : < /dev/tty; } 2>/dev/null; then AUTO=1; fi
    if [ "$AUTO" = 1 ]; then ASSUME_YES=1; AUTO_DEF=1; fi
    setup_ui
    if [ "$AUTO" = 1 ] && [ -z "$MODE" ]; then
        if [ -n "$PANEL_FQDN" ] && [ -n "$NODE_FQDN" ]; then MODE=1
        elif [ -n "$PANEL_FQDN" ]; then MODE=2
        elif [ ${#REMOTE_SPECS[@]} -gt 0 ]; then MODE=4
        else usage; die "Auto mode needs at least --panel (and --node for a full install)."
        fi
    fi
    banner
    preflight
    run_step "Preparing system (base tools)" step_base_tools || die "Could not prepare the system. See ${LOG}"
    virt_check
    if [ -z "$MODE" ]; then
        menu "What do you want to do?" \
            "1  Full install: Panel + Node on this server (one-shot)" \
            "2  Install Panel only" \
            "3  Install Node (Wings) and auto-register to an existing panel" \
            "4  Add remote Node(s) over SSH (run on the panel server)" \
            "5  Upgrade Panel" \
            "6  Upgrade Wings" \
            "7  Install phpMyAdmin" \
            "8  Emergency MariaDB root password reset" \
            "9  Emergency database host reset" \
            "10 Delete Panel (use arrow keys)" \
            "11 Delete Wings (use arrow keys)" \
            "12 Delete Panel + Wings / clear server (use arrow keys)" \
            "0  Exit"
        MODE=$((MENU_SEL + 1))
        [ "$MODE" -eq 13 ] && exit 0
    fi
    case "$MODE" in
        1) mode_full ;;
        2) mode_panel_only ;;
        3) mode_node_api ;;
        4) mode_remote ;;
        5) mode_upgrade_panel ;;
        6) mode_upgrade_wings ;;
        7) mode_phpmyadmin ;;
        8) mode_mariadb_reset ;;
        9) mode_db_host_reset ;;
        10) mode_delete_panel ;;
        11) mode_delete_wings ;;
        12) mode_delete_all ;;
    esac
}

main "$@"
