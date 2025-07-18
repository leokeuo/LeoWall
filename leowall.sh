#!/bin/bash

# ========== COLORS & STYLING ==========
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
RESET=$(tput sgr0)
BOLD=$(tput bold)
DIM=$(tput dim)

# ========== ROOT CHECK ==========
if [[ $EUID -ne 0 ]]; then
    echo "${RED}${BOLD}⛔ ERROR: This script must be run as root!${RESET}"
    echo "${YELLOW}💡 Try: ${GREEN}sudo ./leowall${RESET}"
    exit 1
fi

# ========== ANIMATED LOGO ==========
show_logo() {
    clear
    echo "${CYAN}${BOLD}"
    echo "   ██╗     ███████╗ ██████╗ ██╗    ██╗ █████╗ ██╗     ██╗     "
    echo "   ██║     ██╔════╝██╔═══██╗██║    ██║██╔══██╗██║     ██║     "
    echo "   ██║     █████╗  ██║   ██║██║ █╗ ██║███████║██║     ██║     "
    echo "   ██║     ██╔══╝  ██║   ██║██║███╗██║██╔══██║██║     ██║     "
    echo "   ███████╗███████╗╚██████╔╝╚███╔███╔╝██║  ██║███████╗███████╗"
    echo "   ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
    echo "${RESET}"
    echo "          ${BOLD}🔥 LEO-KEUO FIREWALL MANAGER 🔥${RESET}"
    echo
}

# ========== SERVER INFO ==========
show_server_info() {
    IP=$(hostname -I | awk '{print $1}')
    if [[ -z "$IP" ]]; then
        IP="${RED}Not Available${RESET}"
    fi
    
    echo "${WHITE}${BOLD}🖥️ SERVER INFORMATION${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Local IP Address" "$IP"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Hostname" "$(hostname)"
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"
}

# ========== PROGRESS BAR ==========
show_progress() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spin_chars='⣾⣽⣻⢿⡿⣟⣯⣷'
    local i=0
    
    echo -n "${BLUE}${BOLD}⚡ ${message}... ${RESET}"
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %8 ))
        printf "\r${BLUE}${BOLD}⚡ ${message}... ${spin_chars:$i:1} ${RESET}"
        sleep $delay
    done
    
    printf "\r${GREEN}${BOLD}✅ ${message} - Done!${RESET}\n"
}

# ========== VALIDATE IP ==========
validate_ip() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# ========== FIREWALL SETUP ==========
setup_firewall() {
    show_logo
    echo "${YELLOW}${BOLD}📝 FIREWALL CONFIGURATION${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Enter allowed TCP ports (space-separated)            ${BLUE}│"
    echo "${BLUE}│ ${DIM}SSH (22) is always allowed                          ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    read -p "➤ TCP Ports: " -a TCP_PORTS

    echo
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Enter allowed UDP ports (space-separated)            ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    read -p "➤ UDP Ports: " -a UDP_PORTS

    # Validate ports
    for port in "${TCP_PORTS[@]}" "${UDP_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
            echo "${RED}${BOLD}❌ Error: Invalid port number '$port'${RESET}"
            return 1
        fi
    done

    ALLOWED_TCP=(22 "${TCP_PORTS[@]}")

    echo
    echo "${BLUE}${BOLD}⚡ APPLYING FIREWALL RULES${RESET}"
    
    iptables -F > /dev/null 2>&1 &
    show_progress $! "Flushing existing rules"
    
    iptables -X > /dev/null 2>&1 &
    show_progress $! "Clearing chains"
    
    iptables -t nat -F > /dev/null 2>&1 &
    show_progress $! "Clearing NAT rules"
    
    iptables -t mangle -F > /dev/null 2>&1 &
    show_progress $! "Clearing mangle rules"
    
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Setup logging chain
    iptables -N LOGGING > /dev/null 2>&1 || iptables -F LOGGING
    iptables -A LOGGING -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
    iptables -A LOGGING -j DROP
    iptables -A INPUT -j LOGGING

    echo "${GREEN}${BOLD}🔓 ALLOWED PORTS:${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    for port in "${ALLOWED_TCP[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "TCP Port" "$port"
    done
    for port in "${UDP_PORTS[@]}"; do
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "UDP Port" "$port"
    done
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"

    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    echo "${GREEN}${BOLD}✅ Firewall configured successfully!${RESET}"
}

# ========== ADD PORT ==========
add_port() {
    show_logo
    echo "${YELLOW}${BOLD}➕ ADD NEW PORT${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    while true; do
        read -p "➤ Enter port number (1-65535): " port
        if [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
            break
        else
            echo "${RED}⛔ Invalid port! Must be between 1-65535${RESET}"
        fi
    done

    while true; do
        read -p "➤ Protocol (tcp/udp): " proto
        proto=${proto,,}
        if [[ "$proto" =~ ^(tcp|udp)$ ]]; then
            break
        else
            echo "${RED}⛔ Invalid protocol! Choose 'tcp' or 'udp'${RESET}"
        fi
    done

    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null && {
        echo "${YELLOW}ℹ️ Port $port/$proto is already allowed${RESET}"
        return
    }

    # Rate limiting
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Rate limiting options:                                ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    read -p "➤ Enable rate limiting? (y/n) [n]: " rate_limit
    
    if [[ "$rate_limit" =~ ^[yY]$ ]]; then
        read -p "➤ Max connections per minute [60]: " rate
        rate=${rate:-60}
        
        while ! [[ "$rate" =~ ^[0-9]+$ && $rate -gt 0 ]]; do
            echo "${RED}⛔ Invalid number! Please enter a positive integer${RESET}"
            read -p "➤ Max connections per minute [60]: " rate
            rate=${rate:-60}
        done

        iptables -A INPUT -p $proto --dport $port -m connlimit --connlimit-above $rate -j DROP
        iptables -A INPUT -p $proto --dport $port -m state --state NEW -m recent --set
        iptables -A INPUT -p $proto --dport $port -m state --state NEW -m recent --update --seconds 60 --hitcount $rate -j DROP
        
        echo "${GREEN}${BOLD}✓ Rate limiting enabled: $rate connections/minute${RESET}"
    fi

    iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    
    echo
    echo "${GREEN}${BOLD}✅ PORT ADDED SUCCESSFULLY${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Protocol" "$proto"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Port Number" "$port"
    [[ "$rate_limit" =~ ^[yY]$ ]] && printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Rate Limit" "$rate/min"
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"
}

# ========== REMOVE PORT ==========
remove_port() {
    show_logo
    echo "${YELLOW}${BOLD}➖ REMOVE PORT${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    while true; do
        read -p "➤ Enter port number to remove: " port
        if [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
            break
        else
            echo "${RED}⛔ Invalid port! Must be between 1-65535${RESET}"
        fi
    done

    while true; do
        read -p "➤ Protocol (tcp/udp): " proto
        proto=${proto,,}
        if [[ "$proto" =~ ^(tcp|udp)$ ]]; then
            break
        else
            echo "${RED}⛔ Invalid protocol! Choose 'tcp' or 'udp'${RESET}"
        fi
    done

    # Remove rate limiting rules if they exist
    iptables -D INPUT -p "$proto" --dport "$port" -m connlimit --connlimit-above 0 -j DROP 2>/dev/null
    iptables -D INPUT -p "$proto" --dport "$port" -m state --state NEW -m recent --set 2>/dev/null
    iptables -D INPUT -p "$proto" --dport "$port" -m state --state NEW -m recent --update --seconds 60 --hitcount 0 -j DROP 2>/dev/null
    
    # Remove main rule
    iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    iptables-save > /etc/iptables/rules.v4
    
    echo
    echo "${GREEN}${BOLD}✅ PORT REMOVED SUCCESSFULLY${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${RED}%-26s ${BLUE}│${RESET}\n" "Protocol" "$proto"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${RED}%-26s ${BLUE}│${RESET}\n" "Port Number" "$port"
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"
}

# ========== SHOW OPEN PORTS ==========
show_ports() {
    show_logo
    echo "${YELLOW}${BOLD}🔍 OPEN PORTS${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Listing all externally accessible ports...          ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    echo
    
    echo "${GREEN}${BOLD}TCP Ports:${RESET}"
    ss -tuln | grep 'tcp' | awk '{print $5}' | awk -F':' '{print $NF}' | sort -nu | while read port; do
        printf "  ${BLUE}└─${CYAN} Port ${GREEN}%-5s ${BLUE}(${WHITE}%s${BLUE})${RESET}\n" "$port" "$(grep "$port/tcp" /etc/services | awk '{print $1}' | head -1)"
    done
    
    echo
    echo "${GREEN}${BOLD}UDP Ports:${RESET}"
    ss -tuln | grep 'udp' | awk '{print $5}' | awk -F':' '{print $NF}' | sort -nu | while read port; do
        printf "  ${BLUE}└─${CYAN} Port ${GREEN}%-5s ${BLUE}(${WHITE}%s${BLUE})${RESET}\n" "$port" "$(grep "$port/udp" /etc/services | awk '{print $1}' | head -1)"
    done
}

# ========== SHOW IPTABLES RULES ==========
show_iptables() {
    show_logo
    echo "${YELLOW}${BOLD}📜 IPTABLES RULES${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Listing current firewall rules...                 ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    echo
    
    echo "${GREEN}${BOLD}Current Rules:${RESET}"
    iptables -L -n -v --line-numbers | sed 's/^/  /'
}

# ========== BLOCK IP ==========
block_ip() {
    show_logo
    echo "${YELLOW}${BOLD}🚫 BLOCK IP ADDRESS${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    read -p "➤ Enter IP address to block: " ip
    
    if ! validate_ip "$ip"; then
        echo "${RED}⛔ Invalid IP address format!${RESET}"
        return
    fi
    
    iptables -A INPUT -s "$ip" -j DROP
    iptables-save > /etc/iptables/rules.v4
    
    echo
    echo "${GREEN}${BOLD}✅ IP BLOCKED SUCCESSFULLY${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${RED}%-26s ${BLUE}│${RESET}\n" "Blocked IP" "$ip"
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"
}

# ========== UNBLOCK IP ==========
unblock_ip() {
    show_logo
    echo "${YELLOW}${BOLD}✅ UNBLOCK IP ADDRESS${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    read -p "➤ Enter IP address to unblock: " ip
    
    if ! validate_ip "$ip"; then
        echo "${RED}⛔ Invalid IP address format!${RESET}"
        return
    fi
    
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    iptables-save > /etc/iptables/rules.v4
    
    echo
    echo "${GREEN}${BOLD}✅ IP UNBLOCKED SUCCESSFULLY${RESET}"
    echo "${BLUE}┌──────────────────────┬────────────────────────────┐${RESET}"
    printf "${BLUE}│ ${CYAN}%-20s ${BLUE}│ ${GREEN}%-26s ${BLUE}│${RESET}\n" "Unblocked IP" "$ip"
    echo "${BLUE}└──────────────────────┴────────────────────────────┘${RESET}"
}

# ========== SETUP LOGGING ==========
setup_logging() {
    show_logo
    echo "${YELLOW}${BOLD}📝 LOGGING CONFIGURATION${RESET}"
    echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
    echo "${BLUE}│ ${WHITE}Configure firewall logging options:                 ${BLUE}│${RESET}"
    echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
    
    # Create LOGGING chain if it doesn't exist
    if ! iptables -L LOGGING >/dev/null 2>&1; then
        iptables -N LOGGING
    fi
    
    echo "1) Log all dropped packets"
    echo "2) Log only SSH drop attempts"
    echo "3) Custom logging rule"
    echo "4) Disable logging"
    read -p "➤ Select logging option (1-4): " log_opt
    
    # Flush existing LOGGING chain
    iptables -F LOGGING
    
    case $log_opt in
        1)
            iptables -A LOGGING -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
            iptables -A LOGGING -j DROP
            echo "${GREEN}✅ Logging all dropped packets${RESET}"
            ;;
        2)
            iptables -A LOGGING -p tcp --dport 22 -j LOG --log-prefix "SSH-Attempt: " --log-level 4
            iptables -A LOGGING -p tcp --dport 22 -j DROP
            echo "${GREEN}✅ Logging SSH drop attempts${RESET}"
            ;;
        3)
            read -p "➤ Enter protocol (tcp/udp): " log_proto
            read -p "➤ Enter port number: " log_port
            read -p "➤ Enter log prefix [Custom-Drop]: " log_prefix
            log_prefix=${log_prefix:-Custom-Drop}
            
            iptables -A LOGGING -p $log_proto --dport $log_port -j LOG --log-prefix "$log_prefix: " --log-level 4
            iptables -A LOGGING -p $log_proto --dport $log_port -j DROP
            echo "${GREEN}✅ Custom logging enabled for $log_proto port $log_port${RESET}"
            ;;
        4)
            echo "${YELLOW}⚠️ Logging disabled${RESET}"
            ;;
        *)
            echo "${RED}⛔ Invalid option!${RESET}"
            return 1
            ;;
    esac
    
    # Ensure LOGGING is attached to INPUT
    if ! iptables -C INPUT -j LOGGING >/dev/null 2>&1; then
        iptables -A INPUT -j LOGGING
    fi
    
    iptables-save > /etc/iptables/rules.v4
}

# ========== INSTALL PSAD ==========
install_psad() {
    show_logo
    echo "${YELLOW}${BOLD}🛡️ INSTALLING PSAD (PORT SCAN ATTACK DETECTOR)${RESET}"
    
    # Update packages
    apt update > /dev/null 2>&1 &
    show_progress $! "Updating package lists"
    
    # Install PSAD
    apt install -y psad > /dev/null 2>&1 &
    show_progress $! "Installing PSAD"
    
    # Update signatures
    psad --sig-update > /dev/null 2>&1 &
    show_progress $! "Updating attack signatures"
    
    # Enable and start service
    systemctl enable psad > /dev/null 2>&1 &
    show_progress $! "Enabling PSAD service"
    
    systemctl start psad > /dev/null 2>&1 &
    show_progress $! "Starting PSAD service"
    
    echo "${GREEN}${BOLD}✅ PSAD INSTALLED AND RUNNING${RESET}"
}

# ========== RESET IPTABLES ==========
reset_iptables() {
    show_logo
    echo "${RED}${BOLD}⚠️ WARNING: This will reset ALL firewall rules!${RESET}"
    echo "${YELLOW}All current rules will be deleted and default policies set to ACCEPT.${RESET}"
    echo
    
    read -p "Are you sure? (y/n): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        echo "${BLUE}${BOLD}🔄 Resetting iptables...${RESET}"
        
        # Flush all rules
        iptables -F > /dev/null 2>&1 &
        show_progress $! "Flushing rules"
        
        iptables -X > /dev/null 2>&1 &
        show_progress $! "Deleting chains"
        
        iptables -t nat -F > /dev/null 2>&1 &
        show_progress $! "Clearing NAT"
        
        iptables -t mangle -F > /dev/null 2>&1 &
        show_progress $! "Clearing mangle"
        
        # Set default policies to ACCEPT
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        
        # Save empty rules
        iptables-save > /etc/iptables/rules.v4
        
        echo "${GREEN}${BOLD}✅ iptables has been completely reset!${RESET}"
        echo "${YELLOW}All rules removed and default policy set to ACCEPT.${RESET}"
    else
        echo "${GREEN}${BOLD}🚫 Operation canceled.${RESET}"
    fi
}

# ========== MAIN MENU ==========
main_menu() {
    while true; do
        show_logo
        show_server_info
        
        echo
        echo "${MAGENTA}${BOLD}📜 MAIN MENU${RESET}"
        echo "${BLUE}┌────────────────────────────────────────────────────┐${RESET}"
        printf "${BLUE}│ ${CYAN}1) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Setup Firewall"
        printf "${BLUE}│ ${CYAN}2) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Add Allowed Port"
        printf "${BLUE}│ ${CYAN}3) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Remove Allowed Port"
        printf "${BLUE}│ ${CYAN}4) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Show Open Ports"
        printf "${BLUE}│ ${CYAN}5) ${WHITE}%-42s ${BLUE}│${RESET}\n" "View Firewall Rules"
        printf "${BLUE}│ ${CYAN}6) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Block IP Address"
        printf "${BLUE}│ ${CYAN}7) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Unblock IP Address"
        printf "${BLUE}│ ${CYAN}8) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Install PSAD"
        printf "${BLUE}│ ${CYAN}9) ${WHITE}%-42s ${BLUE}│${RESET}\n" "Configure Logging"
        printf "${BLUE}│ ${CYAN}10) ${RED}%-41s ${BLUE}│${RESET}\n" "RESET ALL IPTABLES RULES"
        printf "${BLUE}│ ${CYAN}0) ${RED}%-42s ${BLUE}│${RESET}\n" "Exit"
        echo "${BLUE}└────────────────────────────────────────────────────┘${RESET}"
        
        read -p "➤ Select an option (0-10): " choice
        
        case $choice in
            1) setup_firewall ;;
            2) add_port ;;
            3) remove_port ;;
            4) show_ports ;;
            5) show_iptables ;;
            6) block_ip ;;
            7) unblock_ip ;;
            8) install_psad ;;
            9) setup_logging ;;
            10) reset_iptables ;;
            0) echo "${GREEN}${BOLD}👋 Goodbye!${RESET}"; exit 0 ;;
            *) echo "${RED}${BOLD}⚠️ Invalid option! Please try again.${RESET}" ;;
        esac
        
        echo
        read -p "${DIM}Press Enter to continue...${RESET}"
    done
}

# ========== INITIALIZATION ==========
show_logo
echo "${BLUE}${BOLD}⚙️ Checking system requirements...${RESET}"

# Check if iptables is installed
if ! command -v iptables &> /dev/null; then
    echo "${YELLOW}ℹ️ Installing iptables...${RESET}"
    apt update > /dev/null 2>&1
    apt install -y iptables > /dev/null 2>&1
fi

# Check if iptables-persistent is installed
if ! dpkg -l | grep -q iptables-persistent; then
    echo "${YELLOW}ℹ️ Installing iptables-persistent...${RESET}"
    apt install -y iptables-persistent > /dev/null 2>&1
fi

# Make script executable and copy to /usr/local/bin
if [ ! -f "/usr/local/bin/leowall" ]; then
    echo "${YELLOW}ℹ️ Installing LeoWall...${RESET}"
    chmod +x "$0"
    cp "$0" /usr/local/bin/leowall
fi

main_menu
