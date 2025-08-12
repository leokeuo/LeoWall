#!/usr/bin/env bash
set -euo pipefail

# ================== COLORS & STYLES (UI THEME) ==================
# Use tput for portability; fall back to plain if not a TTY
RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5); CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7); RESET=$(tput sgr0); BOLD=$(tput bold); DIM=$(tput dim)

# Symbols
ICON_OK="✅"
ICON_ERR="⛔"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_SPARK="⚡"
ICON_RIGHT="▶"
ICON_LEFT="◀"
ICON_SHIELD="🛡️"
ICON_GEARS="⚙️"
ICON_EYE="👁️"
ICON_BLOCK="🚫"
ICON_CHECKS="📜"
ICON_DOWNLOAD="📥"
ICON_UPLOAD="📦"
ICON_NETWORK="🌐"
ICON_PORTS="🔌"
ICON_LOCK="🔒"
ICON_UNLOCK="🔓"

# Box drawing characters
H="─"; V="│"; TL="┌"; TR="┐"; BL="└"; BR="┘"; TJ="┬"; BJ="┴"

# ================== GLOBALS ==================
LEOWALL_VER="2.2"
LOG_FILE="/var/log/leowall.log"
STATE_DIR="/etc/leowall"
ROLLBACK_FLAG_V4="/tmp/leowall-rollback-v4.flag"
ROLLBACK_FLAG_V6="/tmp/leowall-rollback-v6.flag"
BACKUP_V4="$STATE_DIR/rules.v4.backup"
BACKUP_V6="$STATE_DIR/rules.v6.backup"
RULES_V4="$STATE_DIR/rules.v4"
RULES_V6="$STATE_DIR/rules.v6"
EXPORT_DIR="$STATE_DIR/exports"
SSH_PORT_DEFAULT=22
IPSET_OUT_ALLOW="leowall_out_allow"
IPSET_OUT_BLOCK="leowall_out_block"

mkdir -p "$STATE_DIR" "$EXPORT_DIR" || true
touch "$LOG_FILE" || true

# ================== LOGGING & PRIVILEGE ==================
log() { printf "%s %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >/dev/null; }

require_root() {
  # Ensure script runs as root
  if [[ $EUID -ne 0 ]]; then
    echo "${RED}${BOLD}${ICON_ERR} Must be run as root. Try: sudo ./leowall${RESET}"
    exit 1
  fi
}

# ================== UI HELPERS ==================
ui_title() {
  # $1 = title text (centered within a decorative bar)
  local t="$1"
  local line="${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}"
  printf "\n${CYAN}${BOLD}%s\n" "$line"
  printf "  %s\n" "$t"
  printf "%s${RESET}\n\n" "$line"
}

ui_box_open()  { local w=${1:-52}; printf "${BLUE}%s${TJ}%s${TR}${RESET}\n" "$TL$(printf '%*s' $w | tr ' ' "$H")" "$(printf '%*s' 0)"; }
ui_box_head()  { local l="$1"; printf "${BLUE}${V} ${WHITE}${BOLD}%-50s ${BLUE}${V}${RESET}\n" "$l"; }
ui_box_line()  { local l="$1"; printf "${BLUE}${V} ${WHITE}%-50s ${BLUE}${V}${RESET}\n" "$l"; }
ui_box_close() { local w=${1:-52}; printf "${BLUE}%s${BJ}%s${BR}${RESET}\n" "$BL$(printf '%*s' $w | tr ' ' "$H")" "$(printf '%*s' 0)"; }
ui_kv()        { printf "${BLUE}${V} ${CYAN}%-20s ${BLUE}${V} ${GREEN}%-26s ${BLUE}${V}${RESET}\n" "$1" "$2"; }

badge_ok()   { echo "${GREEN}${BOLD}${ICON_OK}${RESET} $*"; }
badge_err()  { echo "${RED}${BOLD}${ICON_ERR}${RESET} $*"; }
badge_info() { echo "${CYAN}${BOLD}${ICON_INFO}${RESET} $*"; }
badge_warn() { echo "${YELLOW}${BOLD}${ICON_WARN}${RESET} $*"; }

spinner() {
  # Simple spinner for background jobs
  local pid=$1 msg=$2; local chars='⣾⣽⣻⢿⡿⣟⣯⣷' i=0
  echo -n "${BLUE}${BOLD}${ICON_SPARK} ${msg}... ${RESET}"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 8 )); printf "\r${BLUE}${BOLD}${ICON_SPARK} ${msg}... ${chars:$i:1} ${RESET}"; sleep 0.1
  done
  printf "\r${GREEN}${BOLD}${ICON_OK} ${msg} - Done!${RESET}\n"
}

pause_wait() { echo; read -rp "${DIM}Press Enter to continue...${RESET}"; }

# ================== RUNTIME HELPERS ==================
validate_ip() {
  # Validate IPv4 address
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<<"$ip"
  [[ $a -le 255 && $b -le 255 && $c -le 255 && $d -le 255 ]]
}

detect_ssh_port() {
  # Detect SSH port from sshd_config or default to 22
  local cfg="/etc/ssh/sshd_config"
  if [[ -f $cfg ]] && grep -qi '^Port' "$cfg"; then
    awk 'tolower($1)=="port"{print $2}' "$cfg" | tail -1
  else
    echo "$SSH_PORT_DEFAULT"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_tools() {
  # Install prerequisites when missing
  ui_title "${ICON_GEARS} System Requirements"
  if ! have_cmd iptables; then
    badge_info "Installing iptables..."
    (apt update >/dev/null 2>&1 && apt install -y iptables >/dev/null 2>&1) & spinner $! "iptables"
  else
    badge_ok "iptables available"
  fi
  if ! have_cmd ip6tables; then
    badge_info "Installing ip6tables..."
    (apt install -y ip6tables >/dev/null 2>&1 || true) & spinner $! "ip6tables"
  else
    badge_ok "ip6tables available"
  fi
  if ! dpkg -l | grep -q iptables-persistent; then
    badge_info "Installing iptables-persistent..."
    (DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent >/dev/null 2>&1 || true) & spinner $! "iptables-persistent"
  else
    badge_ok "iptables-persistent available"
  fi
  if ! have_cmd ipset; then
    badge_info "Installing ipset..."
    (apt install -y ipset >/dev/null 2>&1 || true) & spinner $! "ipset"
  else
    badge_ok "ipset available"
  fi
}

# ================== BRANDING ==================
show_logo() {
  clear
  echo "${BOLD}${CYAN}"
  echo "   ██╗     ███████╗ ██████╗ ██╗    ██╗ █████╗ ██╗     ██╗     "
  echo "   ██║     ██╔════╝██╔═══██╗██║    ██║██╔══██╗██║     ██║     "
  echo "   ██║     █████╗  ██║   ██║██║ █╗ ██║███████║██║     ██║     "
  echo "   ██║     ██╔══╝  ██║   ██║██║███╗██║██╔══██║██║     ██║     "
  echo "   ███████╗███████╗╚██████╔╝╚███╔███╔╝██║  ██║███████╗███████╗"
  echo "   ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
  echo "${RESET}"
  printf "     ${BOLD}${MAGENTA}${ICON_SHIELD} NEXT-GEN FIREWALL MANAGER ${ICON_RIGHT} v%s${RESET}\n\n" "$LEOWALL_VER"
}

server_info() {
  # Compact, card-like server info
  local IPv4=$(hostname -I 2>/dev/null | awk '{print $1}')
  local HN=$(hostname)
  ui_box_open 52
  ui_box_head "🖥  Server Information"
  ui_kv "Local IP Address" "${IPv4:-N/A}"
  ui_kv "Hostname" "$HN"
  ui_box_close 52
}

# ================== RULE GENERATORS ==================
generate_rules_v4() {
  # Generate IPv4 filter table (atomic restore format)
  local ssh_port="$1"; shift
  local allowed_tcp=("$@")
  local allowed_udp=("${ALLOWED_UDP[@]-}")
  cat <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:LOGGING - [0:0]

-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH rate-limit (anti brute-force)
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --set --name SSH
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --update --seconds 60 --hitcount 6 --name SSH -j LOG --log-prefix "SSH-FLOOD: "
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --update --seconds 60 --hitcount 6 --name SSH -j DROP
-A INPUT -p tcp --dport ${ssh_port} -j ACCEPT

# Allowed TCP
$(for p in "${allowed_tcp[@]}"; do echo "-A INPUT -p tcp --dport $p -j ACCEPT"; done)

# Allowed UDP
$(for p in "${allowed_udp[@]}"; do echo "-A INPUT -p udp --dport $p -j ACCEPT"; done)

# Logging sink
-A LOGGING -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
-A LOGGING -j DROP
-A INPUT -j LOGGING
COMMIT
EOF
}

generate_rules_v6() {
  # Generate IPv6 filter table (atomic restore format)
  local ssh_port="$1"; shift
  local allowed_tcp=("$@")
  local allowed_udp=("${ALLOWED_UDP6[@]-}")
  cat <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:LOGGING - [0:0]

-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH rate-limit (anti brute-force)
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --set --name SSH6
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --update --seconds 60 --hitcount 6 --name SSH6 -j LOG --log-prefix "SSH6-FLOOD: "
-A INPUT -p tcp --dport ${ssh_port} -m state --state NEW -m recent --update --seconds 60 --hitcount 6 --name SSH6 -j DROP
-A INPUT -p tcp --dport ${ssh_port} -j ACCEPT

# Allowed TCP
$(for p in "${allowed_tcp[@]}"; do echo "-A INPUT -p tcp --dport $p -j ACCEPT"; done)

# Allowed UDP
$(for p in "${allowed_udp[@]}"; do echo "-A INPUT -p udp --dport $p -j ACCEPT"; done)

# Logging sink
-A LOGGING -j LOG --log-prefix "IP6Tables-Dropped: " --log-level 4
-A LOGGING -j DROP
-A INPUT -j LOGGING
COMMIT
EOF
}

# ================== ATOMIC APPLY & ROLLBACK ==================
atomic_apply() {
  # Apply rules with a 60s rollback window to avoid lockouts
  # $1 = v4|v6 ; $2 = path to rules file
  local fam="$1" rules="$2"
  mkdir -p /etc/iptables
  if [[ $fam == "v4" ]]; then
    iptables-save > "$BACKUP_V4"
    echo "1" > "$ROLLBACK_FLAG_V4"
    (sleep 60; [[ -f "$ROLLBACK_FLAG_V4" ]] && log "Auto-rollback v4" && iptables-restore < "$BACKUP_V4") &
    iptables-restore < "$rules"
    rm -f "$ROLLBACK_FLAG_V4"
    iptables-save > /etc/iptables/rules.v4
  else
    if have_cmd ip6tables; then
      ip6tables-save > "$BACKUP_V6" || true
      echo "1" > "$ROLLBACK_FLAG_V6"
      (sleep 60; [[ -f "$ROLLBACK_FLAG_V6" ]] && log "Auto-rollback v6" && ip6tables-restore < "$BACKUP_V6") &
      ip6tables-restore < "$rules" || true
      rm -f "$ROLLBACK_FLAG_V6" || true
      ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    fi
  fi
}

# ================== OUTBOUND MANAGEMENT ==================
ensure_ipsets() {
  # Ensure ipsets for allow/block exist
  ipset list "$IPSET_OUT_ALLOW" >/dev/null 2>&1 || ipset create "$IPSET_OUT_ALLOW" hash:ip
  ipset list "$IPSET_OUT_BLOCK" >/dev/null 2>&1 || ipset create "$IPSET_OUT_BLOCK" hash:ip
}

apply_outbound_policy() {
  # Set OUTPUT policy and baseline allows
  local policy="$1"
  iptables -P OUTPUT "$policy"
  if [[ "$policy" == "DROP" ]]; then
    iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || iptables -A OUTPUT -o lo -j ACCEPT
    iptables -C OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ensure_ipsets
    iptables -C OUTPUT -m set --match-set "$IPSET_OUT_ALLOW" dst -j ACCEPT 2>/dev/null || iptables -A OUTPUT -m set --match-set "$IPSET_OUT_ALLOW" dst -j ACCEPT
    iptables -C OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -C OUTPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
  fi
  ensure_ipsets
  iptables -C OUTPUT -m set --match-set "$IPSET_OUT_BLOCK" dst -j REJECT 2>/dev/null || iptables -A OUTPUT -m set --match-set "$IPSET_OUT_BLOCK" dst -j REJECT
  iptables-save > /etc/iptables/rules.v4
}

outbound_menu() {
  show_logo; server_info
  ui_title "${ICON_NETWORK} Outbound Management"
  echo "  ${ICON_RIGHT} 1) Show Status"
  echo "  ${ICON_RIGHT} 2) Set OUTPUT Policy (ACCEPT/DROP)"
  echo "  ${ICON_RIGHT} 3) Add IP/CIDR to Allowlist"
  echo "  ${ICON_RIGHT} 4) Remove from Allowlist"
  echo "  ${ICON_RIGHT} 5) Add IP/CIDR to Blocklist"
  echo "  ${ICON_RIGHT} 6) Remove from Blocklist"
  echo
  read -rp "  Select: " o
  case $o in
    1)
      ui_box_open 52
      ui_box_head "Current Outbound"
      ui_kv "Policy" "$(iptables -S OUTPUT | sed -n '1p' | awk '{print $3}')"
      ui_box_close 52
      echo
      badge_info "Allowlist:"; ipset list "$IPSET_OUT_ALLOW" 2>/dev/null || echo " (empty)"
      echo
      badge_info "Blocklist:"; ipset list "$IPSET_OUT_BLOCK" 2>/dev/null || echo " (empty)"
      ;;
    2)
      read -rp "  Policy (ACCEPT/DROP): " pol
      pol=${pol^^}; [[ $pol =~ ^(ACCEPT|DROP)$ ]] || { badge_err "Invalid policy"; pause_wait; return; }
      apply_outbound_policy "$pol"; badge_ok "Applied."
      ;;
    3)
      ensure_ipsets; read -rp "  IP/CIDR: " ip
      ipset add "$IPSET_OUT_ALLOW" "$ip" 2>/dev/null && badge_ok "Added." || badge_warn "Already exists/invalid."
      iptables-save > /etc/iptables/rules.v4
      ;;
    4)
      ensure_ipsets; read -rp "  IP/CIDR: " ip
      ipset del "$IPSET_OUT_ALLOW" "$ip" 2>/dev/null && badge_ok "Removed." || badge_warn "Not found."
      iptables-save > /etc/iptables/rules.v4
      ;;
    5)
      ensure_ipsets; read -rp "  IP/CIDR: " ip
      ipset add "$IPSET_OUT_BLOCK" "$ip" 2>/dev/null && badge_ok "Added." || badge_warn "Already exists/invalid."
      iptables-save > /etc/iptables/rules.v4
      ;;
    6)
      ensure_ipsets; read -rp "  IP/CIDR: " ip
      ipset del "$IPSET_OUT_BLOCK" "$ip" 2>/dev/null && badge_ok "Removed." || badge_warn "Not found."
      iptables-save > /etc/iptables/rules.v4
      ;;
    *) badge_warn "Cancelled." ;;
  esac
  pause_wait
}

# ================== INBOUND FEATURES ==================
quick_allow_current_ssh() {
  # Ensure current SSH session stays whitelisted
  if [[ -n ${SSH_CONNECTION:-} ]]; then
    local src_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
    local dst_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
    iptables -C INPUT -p tcp -s "$src_ip" --dport "$dst_port" -j ACCEPT 2>/dev/null || \
      iptables -I INPUT 1 -p tcp -s "$src_ip" --dport "$dst_port" -j ACCEPT
  fi
}

setup_firewall() {
  # Guided inbound setup (atomic apply, v4/v6)
  show_logo; server_info
  ui_title "${ICON_LOCK} Firewall Setup"
  local SSH_PORT; SSH_PORT=$(detect_ssh_port)
  echo "  ${ICON_INFO} SSH port detected: ${GREEN}${SSH_PORT}${RESET}"
  echo "  Enter allowed ${BOLD}TCP${RESET} ports (space-separated). SSH is always allowed."
  read -rp "  TCP > " -a TCP_PORTS
  echo "  Enter allowed ${BOLD}UDP${RESET} ports (space-separated)."
  read -rp "  UDP > " -a UDP_PORTS

  for port in "${TCP_PORTS[@]:-}" "${UDP_PORTS[@]:-}"; do
    [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || { badge_err "Invalid port: $port"; pause_wait; return 1; }
  done

  ALLOWED_TCP=("$SSH_PORT" "${TCP_PORTS[@]-}")
  ALLOWED_UDP=("${UDP_PORTS[@]-}")
  ALLOWED_UDP6=("${UDP_PORTS[@]-}")

  generate_rules_v4 "$SSH_PORT" "${ALLOWED_TCP[@]}" > "$RULES_V4"
  generate_rules_v6 "$SSH_PORT" "${ALLOWED_TCP[@]}" > "$RULES_V6"

  quick_allow_current_ssh
  log "Applying IPv4 rules (atomic)"
  atomic_apply v4 "$RULES_V4"
  if have_cmd ip6tables; then
    log "Applying IPv6 rules (atomic)"
    atomic_apply v6 "$RULES_V6"
  fi

  badge_ok "Firewall configured successfully."
  badge_info "Outbound policy is ${GREEN}ACCEPT${RESET} by default. See 'Outbound Management' to restrict."
  pause_wait
}

add_port() {
  # Add inbound allowed port rule (v4 + v6 when available)
  show_logo; server_info
  ui_title "${ICON_UNLOCK} Add Allowed Port"
  while :; do read -rp "  Port (1-65535): " port; [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] && break || badge_err "Invalid"; done
  while :; do read -rp "  Protocol (tcp/udp): " proto; proto=${proto,,}; [[ $proto =~ ^(tcp|udp)$ ]] && break || badge_err "Invalid"; done
  if iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
    badge_warn "Already allowed."
  else
    iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    have_cmd ip6tables && ip6tables -A INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    have_cmd ip6tables && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    badge_ok "Added."
  fi
  pause_wait
}

remove_port() {
  # Remove inbound allowed port rule (v4 + v6 when available)
  show_logo; server_info
  ui_title "${ICON_LOCK} Remove Allowed Port"
  while :; do read -rp "  Port: " port; [[ $port =~ ^[0-9]+$ ]] && break || badge_err "Invalid"; done
  while :; do read -rp "  Protocol (tcp/udp): " proto; proto=${proto,,}; [[ $proto =~ ^(tcp|udp)$ ]] && break || badge_err "Invalid"; done
  iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
  iptables-save > /etc/iptables/rules.v4
  have_cmd ip6tables && ip6tables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
  have_cmd ip6tables && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  badge_ok "Removed."
  pause_wait
}

show_ports() {
  # Pretty list of listening TCP/UDP ports
  show_logo; server_info
  ui_title "${ICON_PORTS} Open Ports"
  echo "  ${BOLD}TCP:${RESET}"
  ss -tuln | awk '/tcp/ {print $5}' | awk -F':' '{print $NF}' | sort -nu | while read -r p; do
    svc=$(grep -E "^.+[[:space:]]+$p/tcp" /etc/services 2>/dev/null | awk '{print $1}' | head -1)
    printf "    ${BLUE}└─${CYAN} Port ${GREEN}%-5s ${BLUE}(${WHITE}%s${BLUE})${RESET}\n" "$p" "${svc:-Unknown}"
  done
  echo; echo "  ${BOLD}UDP:${RESET}"
  ss -tuln | awk '/udp/ {print $5}' | awk -F':' '{print $NF}' | sort -nu | while read -r p; do
    svc=$(grep -E "^.+[[:space:]]+$p/udp" /etc/services 2>/dev/null | awk '{print $1}' | head -1)
    printf "    ${BLUE}└─${CYAN} Port ${GREEN}%-5s ${BLUE}(${WHITE}%s${BLUE})${RESET}\n" "$p" "${svc:-Unknown}"
  done
  pause_wait
}

show_iptables() {
  # Compact summary + detailed listing
  show_logo; server_info
  ui_title "${ICON_CHECKS} Current Rules"
  ui_box_open 52
  ui_box_head "IPv4 Summary"
  ui_kv "INPUT rules"  "$(iptables -S INPUT | grep -c '^-A')"
  ui_kv "OUTPUT rules" "$(iptables -S OUTPUT | grep -c '^-A')"
  ui_kv "FORWARD rules" "$(iptables -S FORWARD | grep -c '^-A')"
  ui_box_close 52
  echo
  iptables -L -n -v --line-numbers | sed 's/^/  /'
  if have_cmd ip6tables; then
    echo
    ui_box_open 52
    ui_box_head "IPv6 Summary"
    ui_box_close 52
    ip6tables -L -n -v --line-numbers 2>/dev/null | sed 's/^/  /' || true
  fi
  pause_wait
}

block_ip() {
  # Add a DROP rule for a source IP
  show_logo; server_info
  ui_title "${ICON_BLOCK} Block IP"
  read -rp "  IP: " ip; validate_ip "$ip" || { badge_err "Invalid IP"; pause_wait; return; }
  iptables -C INPUT -s "$ip" -j DROP 2>/dev/null || iptables -A INPUT -s "$ip" -j DROP
  iptables-save > /etc/iptables/rules.v4
  badge_ok "Blocked ${ip}"
  pause_wait
}

unblock_ip() {
  # Remove a DROP rule for a source IP
  show_logo; server_info
  ui_title "${ICON_UNLOCK} Unblock IP"
  read -rp "  IP: " ip; validate_ip "$ip" || { badge_err "Invalid IP"; pause_wait; return; }
  iptables -D INPUT -s "$ip" -j DROP 2>/dev/null || true
  iptables-save > /etc/iptables/rules.v4
  badge_ok "Unblocked ${ip}"
  pause_wait
}

setup_logging() {
  # Configure LOGGING chain behavior
  show_logo; server_info
  ui_title "${ICON_EYE} Logging Configuration"
  echo "  ${ICON_RIGHT} 1) Log all dropped packets"
  echo "  ${ICON_RIGHT} 2) Log SSH drop attempts only"
  echo "  ${ICON_RIGHT} 3) Custom (protocol/port)"
  echo "  ${ICON_RIGHT} 4) Disable logging"
  echo
  read -rp "  Select (1-4): " o
  iptables -N LOGGING 2>/dev/null || true
  iptables -F LOGGING
  case $o in
    1) iptables -A LOGGING -j LOG --log-prefix "IPTables-Dropped: " --log-level 4; iptables -A LOGGING -j DROP; badge_ok "Enabled (all)";;
    2) local sp; sp=$(detect_ssh_port); iptables -A LOGGING -p tcp --dport "$sp" -j LOG --log-prefix "SSH-Attempt: " --log-level 4; iptables -A LOGGING -p tcp --dport "$sp" -j DROP; badge_ok "Enabled (SSH)";;
    3) read -rp "  Protocol (tcp/udp): " pr; read -rp "  Port: " po; read -rp "  Prefix [Custom-Drop]: " pre; pre=${pre:-Custom-Drop}
       iptables -A LOGGING -p "$pr" --dport "$po" -j LOG --log-prefix "$pre: " --log-level 4; iptables -A LOGGING -p "$pr" --dport "$po" -j DROP; badge_ok "Custom rule added";;
    4) badge_warn "Logging disabled";;
    *) badge_err "Invalid option"; pause_wait; return;;
  esac
  iptables -C INPUT -j LOGGING 2>/dev/null || iptables -A INPUT -j LOGGING
  iptables-save > /etc/iptables/rules.v4
  pause_wait
}

install_psad() {
  # Install and start PSAD (port-scan detector)
  show_logo; server_info
  ui_title "${ICON_SHIELD} Install PSAD"
  (apt update >/dev/null 2>&1) & spinner $! "Updating package lists"
  (apt install -y psad >/dev/null 2>&1) & spinner $! "Installing PSAD"
  (psad --sig-update >/dev/null 2>&1) & spinner $! "Updating attack signatures"
  (systemctl enable psad >/dev/null 2>&1) & spinner $! "Enabling PSAD service"
  (systemctl start psad >/dev/null 2>&1) & spinner $! "Starting PSAD service"
  badge_ok "PSAD is installed and running."
  pause_wait
}

reset_iptables() {
  # Danger: reset all rules and set default policies to ACCEPT
  show_logo; server_info
  ui_title "${ICON_WARN} Reset ALL iptables Rules"
  read -rp "  Are you sure? (y/n): " c
  [[ $c =~ ^[yY]$ ]] || { badge_warn "Cancelled."; pause_wait; return; }
  (iptables -F; iptables -X; iptables -t nat -F; iptables -t mangle -F;
   iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT;
   iptables-save > /etc/iptables/rules.v4) & spinner $! "Resetting IPv4"
  if have_cmd ip6tables; then
    (ip6tables -F; ip6tables -X; ip6tables -t nat -F 2>/dev/null || true; ip6tables -t mangle -F 2>/dev/null || true;
     ip6tables -P INPUT ACCEPT; ip6tables -P FORWARD ACCEPT; ip6tables -P OUTPUT ACCEPT;
     ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true) & spinner $! "Resetting IPv6"
  fi
  badge_ok "Reset complete."
  pause_wait
}

export_rules() {
  # Export current rules to timestamped files
  show_logo; server_info
  ui_title "${ICON_UPLOAD} Export Rules"
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  iptables-save > "$EXPORT_DIR/rules.$ts.v4"
  have_cmd ip6tables && ip6tables-save > "$EXPORT_DIR/rules.$ts.v6" 2>/dev/null || true
  badge_ok "Saved to: $EXPORT_DIR"
  pause_wait
}

import_rules() {
  # Import rules from files with atomic apply
  show_logo; server_info
  ui_title "${ICON_DOWNLOAD} Import Rules"
  echo "  Provide path to IPv4 rules file:"
  read -r f4; [[ -f $f4 ]] || { badge_err "File not found"; pause_wait; return; }
  echo "  Provide path to IPv6 rules file (optional):"
  read -r f6
  cp "$f4" "$RULES_V4"; atomic_apply v4 "$RULES_V4"
  if [[ -n ${f6:-} && -f $f6 && $(have_cmd ip6tables && echo 1 || echo 0) -eq 1 ]]; then
    cp "$f6" "$RULES_V6"; atomic_apply v6 "$RULES_V6"
  fi
  badge_ok "Imported."
  pause_wait
}

# ================== INBOUND SUBMENU ==================
inbound_menu() {
  while true; do
    show_logo; server_info
    ui_title "${ICON_LOCK} Inbound Management"
    echo "  ${ICON_RIGHT} 1) Setup Firewall (atomic, IPv4/IPv6)"
    echo "  ${ICON_RIGHT} 2) Add Allowed Port"
    echo "  ${ICON_RIGHT} 3) Remove Allowed Port"
    echo "  ${ICON_RIGHT} 4) View Firewall Rules"
    echo "  ${ICON_RIGHT} 5) Block IP Address"
    echo "  ${ICON_RIGHT} 6) Unblock IP Address"
    echo "  ${ICON_RIGHT} 7) Configure Logging"
    echo "  ${ICON_LEFT}  0) Back"
    echo
    read -rp "  Select (0-7): " ib
    case $ib in
      1) quick_allow_current_ssh; setup_firewall ;;
      2) add_port ;;
      3) remove_port ;;
      4) show_iptables ;;
      5) block_ip ;;
      6) unblock_ip ;;
      7) setup_logging ;;
      0) break ;;
      *) badge_err "Invalid option" ;;
    esac
  done
}

# ================== MAIN MENU ==================
main_menu() {
  while true; do
    show_logo; server_info
    ui_title "${ICON_CHECKS} MAIN MENU"
    echo "  ${ICON_RIGHT} 1) Inbound Management ${ICON_RIGHT}"
    echo "  ${ICON_RIGHT} 2) Outbound Management"
    echo "  ${ICON_RIGHT} 3) Show Open Ports"
    echo "  ${ICON_RIGHT} 4) Install PSAD"
    echo "  ${ICON_RIGHT} 5) Export Rules"
    echo "  ${ICON_RIGHT} 6) Import Rules"
    echo "  ${ICON_WARN}  7) RESET ALL IPTABLES RULES"
    echo "  ${ICON_LEFT}  0) Exit"
    echo
    read -rp "  Select (0-7): " ch
    case $ch in
      1) inbound_menu ;;
      2) outbound_menu ;;
      3) show_ports ;;
      4) install_psad ;;
      5) export_rules ;;
      6) import_rules ;;
      7) reset_iptables ;;
      0) echo; badge_ok "Goodbye!"; exit 0 ;;
      *) badge_err "Invalid option" ;;
    esac
  done
}

# ================== INIT ==================
require_root
ensure_tools

# Install self to PATH once
if [[ ! -f "/usr/local/bin/leowall" || "$0" != "/usr/local/bin/leowall" ]]; then
  badge_info "Installing LeoWall to /usr/local/bin..."
  install -m 0755 "$0" /usr/local/bin/leowall
  badge_ok "Installed."
  sleep 0.6
fi

main_menu
