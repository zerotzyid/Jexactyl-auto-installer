#!/usr/bin/env bash
# ==============================================================================
#  Jexactyl Auto Installer  -  one-shot Panel + Node setup
#  Copyright (c) 2026 ZeroTzyID  -  https://github.com/zerotzyid
#
#  Portions derived from the original Jexactyl installation script
#  (c) 2022 Vikas Dongre, distributed under the MIT License.
# ==============================================================================

SCRIPT_VERSION="2.0.0"
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
PHP_VERSION="8.1"
F2B_BACKEND="auto"
LOC_SHORT="zerotzyid"
LOC_LONG="ZeroTzyID Default Location"

MODE=""
ASSUME_YES=0
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

# ------------------------------------------------------------------- UI -------
rep(){ local s="" i; for ((i=0; i<$2; i++)); do s+="$1"; done; printf '%s' "$s"; }

ok(){   printf "  ${GRN}✔${R} %s\n" "$*"; }
info(){ printf "  ${CYA}i${R} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${R} %s\n" "$*"; }
err(){  printf "  ${RED}✘${R} %s\n" "$*" >&2; }
die(){  err "$*"; exit 1; }
section(){ printf "\n  ${B}${PUR}▌${R} ${B}%s${R}\n" "$1"; }

row(){ # plain_text colored_text
    local pad=$(( 60 - ${#1} ))
    [ $pad -lt 0 ] && pad=0
    printf "  ${PUR}│${R}%s%*s${PUR}│${R}\n" "$2" "$pad" ""
}

banner(){
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
    printf "\r\e[K"
}

fail_tail(){
    printf "\n  ${DIM}Last log lines (%s):${R}\n" "$LOG"
    tail -n 12 "$LOG" 2>/dev/null | sed "s/^/    /"
    printf "\n"
}

run_step(){ # label function [args]
    local label="$1" pre="" pb="" t0=$SECONDS rc
    shift
    STEP_NOW=$((STEP_NOW + 1))
    if [ "$STEP_TOTAL" -gt 0 ]; then
        pre="[$STEP_NOW/$STEP_TOTAL] "
        pb="$(bar $((STEP_NOW - 1)) "$STEP_TOTAL")"
    fi
    echo "=== STEP ${pre}${label} ($(date '+%F %T'))" >> "$LOG"
    spinner_start "$pre" "$label" "$pb"
    "$@" >> "$LOG" 2>&1 < /dev/null
    rc=$?
    spinner_stop
    if [ $rc -eq 0 ]; then
        printf "  ${GRN}✔${R} ${GRY}%s${R}%s ${DIM}(%ss)${R}\n" "$pre" "$label" "$((SECONDS - t0))"
    else
        printf "  ${RED}✘${R} ${GRY}%s${R}%s\n" "$pre" "$label"
        fail_tail
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
    local fqdn="$1" want="$2" label="$3" got a
    while true; do
        got=$(resolve_ip "$fqdn")
        if [ -n "$got" ] && [ "$got" = "$want" ]; then ok "DNS ${label}: ${fqdn} -> ${got}"; return 0; fi
        warn "DNS ${label}: ${fqdn} resolves to '${got:-nothing}', expected ${want}"
        info "Create an A record for ${fqdn} pointing to ${want} (Cloudflare: DNS only / grey cloud)."
        [ "$ASSUME_YES" = 1 ] && return 1
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

step_base_tools(){
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
step_repos(){
    req apt-get update -y || return 1
    req apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release wget sudo || return 1
    if [ "$lsb_dist" = ubuntu ]; then
        req env LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || return 1
        add-apt-repository -y ppa:redislabs/redis || echo "redislabs PPA unavailable, using distribution redis."
    else
        req curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/deb.sury.org-php.gpg || return 1
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi
    curl -fsSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash || echo "MariaDB repo setup failed, using distribution MariaDB."
    req apt-get update -y
}

step_packages(){
    req apt-get install -y "php${PHP_VERSION}" php${PHP_VERSION}-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} \
        mariadb-server nginx tar unzip git redis-server cron acl certbot jq ufw fail2ban dnsutils || return 1
    if [ "$F2B_BACKEND" = systemd ]; then apt-get install -y python3-systemd || true; fi
    systemctl enable --now redis-server "php${PHP_VERSION}-fpm" cron mariadb nginx || return 1
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
    systemctl restart nginx
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
try {
    $node = Pterodactyl\Models\Node::findOrFail((int) $argv[1]);
    $info = app(Pterodactyl\Repositories\Wings\DaemonConfigurationRepository::class)->setNode($node)->getSystemInformation();
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
echo Pterodactyl\Models\Node::findOrFail((int) $argv[1])->getYamlConfiguration();
PHP
    cat > "$WORK/create_node.php" <<'PHP'
<?php
require '/var/www/jexactyl/vendor/autoload.php';
$app = require '/var/www/jexactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$node = app(Pterodactyl\Services\Nodes\NodeCreationService::class)->handle([
    'name' => getenv('ZT_NAME'),
    'description' => 'Auto-created by ZeroTzyID installer',
    'location_id' => (int) getenv('ZT_LOC'),
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
    'daemonBase' => '/var/lib/pterodactyl/volumes',
    'daemonSFTP' => 2022,
    'daemonListen' => 8080,
]);
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
    local fqdn="$1" ip="$2" loc_id name
    name="ZT-${fqdn%%.*}"
    cd "$PANEL_DIR" || return 1
    write_php_helpers
    loc_id=$(sql "SELECT id FROM locations WHERE short='${LOC_SHORT}' LIMIT 1")
    if [ -z "$loc_id" ]; then
        req php artisan p:location:make --no-interaction --short="$LOC_SHORT" --long="$LOC_LONG" || return 1
        loc_id=$(sql "SELECT id FROM locations WHERE short='${LOC_SHORT}' LIMIT 1")
    fi
    [ -n "$loc_id" ] || { echo "Location could not be created."; return 1; }
    NODE_ID=$(sql "SELECT id FROM nodes WHERE fqdn='${fqdn}' ORDER BY id DESC LIMIT 1")
    if [ -z "$NODE_ID" ]; then
        php artisan p:node:make --no-interaction --name="$name" --description="Auto-created by ZeroTzyID installer" \
            --locationId="$loc_id" --fqdn="$fqdn" --public=1 --scheme=https --proxy=0 --maintenance=0 \
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
    CUR_FQDN=""; CUR_SSH_HOST=""; CUR_SSH_PORT=""; CUR_SSH_USER=""; CUR_SSH_PASS=""; CUR_SSH_KEY=""
    ask CUR_FQDN "Node FQDN (e.g. node2.example.com)" "" is_fqdn
    ask CUR_SSH_HOST "SSH host/IP of that server" "$CUR_FQDN"
    ask CUR_SSH_PORT "SSH port" "22"
    ask CUR_SSH_USER "SSH user (must be root)" "root"
    menu "SSH authentication" "1  Password" "2  Private key file"
    if [ "$MENU_SEL" -eq 0 ]; then
        ask_secret CUR_SSH_PASS "SSH password"
        command -v sshpass >/dev/null || { info "Installing sshpass..."; apt-get install -y sshpass >> "$LOG" 2>&1; }
    else
        ask CUR_SSH_KEY "Path to private key" "/root/.ssh/id_rsa"
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
    local loc existing body
    api GET /locations | jq -e '.data' >/dev/null || { echo "API key rejected by the panel."; return 1; }
    loc=$(api GET /locations | jq -r '.data[0].attributes.id // empty')
    if [ -z "$loc" ]; then
        loc=$(api POST /locations "{\"short\":\"${LOC_SHORT}\",\"long\":\"${LOC_LONG}\"}" | jq -r '.attributes.id // empty')
    fi
    [ -n "$loc" ] || { echo "Could not get/create a location."; return 1; }
    calc_res "$(res_script | bash)"
    existing=$(api GET "/nodes?filter[fqdn]=${CUR_FQDN}" | jq -r '.data[0].attributes.id // empty')
    if [ -n "$existing" ]; then
        NODE_ID="$existing"; echo "Node already exists (ID ${NODE_ID}), reusing."
    else
        body=$(jq -n --arg name "ZT-${CUR_FQDN%%.*}" --arg fqdn "$CUR_FQDN" --argjson loc "$loc" \
            --argjson mem "$NODE_MEM" --argjson disk "$NODE_DISK" \
            '{name:$name,description:"Auto-created by ZeroTzyID installer",location_id:$loc,fqdn:$fqdn,scheme:"https",behind_proxy:false,public:true,memory:$mem,memory_overallocate:0,disk:$disk,disk_overallocate:0,daemon_base:"/var/lib/pterodactyl/volumes",daemon_sftp:2022,daemon_listen:8080,upload_size:100}')
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
}

# ------------------------------------------------------------ modes ----------
panel_exists(){ [ -f "$PANEL_DIR/.env" ]; }

collect_panel_inputs(){
    section "Panel details"
    ask EMAIL "Admin email (also used for Let's Encrypt)" "" is_email
    ask PANEL_FQDN "Panel FQDN (panel.example.com)" "" is_fqdn
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

mode_full(){
    panel_exists && die "Jexactyl already exists in ${PANEL_DIR}. Use 'Add remote node' or the upgrade options."
    collect_panel_inputs
    collect_node_inputs
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
    if confirm "Also add remote node(s) over SSH?" n; then
        deploy_remote_nodes
        run_flow "Finalizing permissions|step_finalize"
    fi
    summary
}

mode_panel_only(){
    panel_exists && die "Jexactyl already exists in ${PANEL_DIR}."
    collect_panel_inputs
    section "Installing"
    panel_flow_items
    FLOW_PANEL+=("Finalizing permissions|step_finalize")
    run_flow "${FLOW_PANEL[@]}" || die "Panel installation failed. See ${LOG}"
    save_credentials
    summary
}

mode_node_api(){
    section "Existing panel"
    ask PANEL_FQDN "Panel FQDN (already installed)" "" is_fqdn
    info "Create an Application API key in the panel: Admin > Application API (Read & Write for Nodes, Locations, Allocations)."
    ask_secret API_KEY "Application API key (ptla_...)" is_apikey
    ask EMAIL "Email for Let's Encrypt" "" is_email
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
    ask EMAIL "Email for Let's Encrypt" "" is_email
    ask PORT_RANGE "Allocation port range" "25565-25600" is_ports
    deploy_remote_nodes
    run_flow "Finalizing permissions|step_finalize"
    summary
}

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
  --harden             Apply extra kernel hardening (optional)
  -y, --yes            Accept defaults, no confirmation prompts
  -h, --help           Show this help

Fully automatic example:
  bash install.sh --full --panel panel.example.com --node node.example.com --email you@example.com -y
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
            --harden) HARDEN=1 ;;
            -y|--yes) ASSUME_YES=1 ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

main(){
    parse_args "$@"
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
            "0  Exit"
        MODE=$((MENU_SEL + 1))
        [ "$MODE" -eq 10 ] && exit 0
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
    esac
}

main "$@"
