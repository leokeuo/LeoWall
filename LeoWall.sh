#!/bin/bash

# ========== COLORS ==========
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# ========== LOGO ==========
show_logo() {
    clear
    echo "${CYAN}${BOLD}"
    echo "██╗     ███████╗ ██████╗ ██╗    ██╗ █████╗ ██╗     ██╗     "
    echo "██║     ██╔════╝██╔═══██╗██║    ██║██╔══██╗██║     ██║     "
    echo "██║     █████╗  ██║   ██║██║ █╗ ██║███████║██║     ██║     "
    echo "██║     ██╔══╝  ██║   ██║██║███╗██║██╔══██║██║     ██║     "
    echo "███████╗███████╗╚██████╔╝╚███╔███╔╝██║  ██║███████╗███████╗"
    echo "╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
    echo "     🔥 LeoWall Firewall Manager 🔥"
    echo "${RESET}"
}

# ========== INSTALL PSAD ==========
install_psad() {
    show_logo
    echo "${BLUE}🔧 Installing psad and iptables-persistent...${RESET}"
    sudo apt update
    sudo apt install -y psad iptables-persistent

    echo "${BLUE}🔄 Updating PSAD signatures...${RESET}"
    sudo psad --sig-update

    echo "${BLUE}⚙️ Configuring iptables logging for PSAD...${RESET}"
    sudo iptables -A INPUT -j LOG --log-prefix "PSAD: " --log-level 4

    echo "${BLUE}🚀 Restarting psad service...${RESET}"
    sudo systemctl restart psad
    sudo systemctl enable psad

    echo "${GREEN}✅ PSAD installed and logging enabled (without config changes).${RESET}"
    sleep 2
}

# ========== FIREWALL SETUP ==========
setup_firewall() {
    show_logo
    echo "${YELLOW}💬 Enter allowed TCP ports (space-separated)."
    echo "ℹ️ SSH (22) will be opened by default.${RESET}"
    read -p "✅ Ports: " -a USER_PORTS

    OPEN_PORTS=(22 "${USER_PORTS[@]}")

    echo "${BLUE}🚿 Flushing existing rules...${RESET}"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    echo "${GREEN}✅ Opening TCP ports:${RESET}"
    for port in "${OPEN_PORTS[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        echo "   → TCP port ${GREEN}$port${RESET} allowed"
    done

    iptables-save > /etc/iptables/rules.v4
    echo "${GREEN}✅ Firewall rules saved permanently.${RESET}"
}

# ========== MODIFY FIREWALL ==========
add_port() {
    show_logo
    read -p "➕ Enter TCP port to allow: " port
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -le 65535 ]; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "${YELLOW}⚠️ Port $port is already allowed.${RESET}"
        else
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            iptables-save > /etc/iptables/rules.v4
            echo "${GREEN}✔️ Port $port has been allowed and saved.${RESET}"
        fi
    else
        echo "${RED}❌ Invalid port number.${RESET}"
    fi
}

remove_port() {
    show_logo
    read -p "➖ Enter TCP port to remove: " port
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -le 65535 ]; then
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables-save > /etc/iptables/rules.v4
        echo "${GREEN}✔️ Port $port removed and rules saved.${RESET}"
    else
        echo "${RED}❌ Invalid port number.${RESET}"
    fi
}

# ========== OTHER ACTIONS ==========
reset_firewall() {
    show_logo
    echo "${YELLOW}⚠️ Resetting firewall to open everything...${RESET}"

    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    iptables-save > /etc/iptables/rules.v4
    echo "${GREEN}✅ All rules flushed. Everything is now open.${RESET}"
}

show_ports() {
    show_logo
    echo "${CYAN}🔍 Services currently listening on ports:${RESET}"
    ss -tuln
}

show_iptables() {
    show_logo
    echo "${CYAN}📜 Allowed TCP ports in iptables:${RESET}"
    iptables -S | grep -- '--dport' || echo "${YELLOW}⚠️ No specific ports allowed yet.${RESET}"
}

block_ip() {
    show_logo
    read -p "🚫 Enter IP to block: " ip
    iptables -A INPUT -s "$ip" -j DROP
    iptables-save > /etc/iptables/rules.v4
    echo "${RED}❌ Blocked IP: $ip${RESET}"
}

unblock_ip() {
    show_logo
    read -p "✅ Enter IP to unblock: " ip
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null && \
    iptables-save > /etc/iptables/rules.v4 && \
    echo "${GREEN}✔️ Unblocked IP: $ip${RESET}" || \
    echo "${YELLOW}⚠️ IP not found in block list.${RESET}"
}

# ========== MAIN MENU ==========
while true; do
    show_logo
    echo "${MAGENTA}${BOLD}📋 MAIN MENU:${RESET}"
    echo "${MAGENTA}══════════════════════════════════════════════${RESET}"
    echo "  ${CYAN}1)${RESET} 🔐 Set up firewall (allow selected TCP ports)"
    echo "  ${CYAN}2)${RESET} ➕ Add a new allowed TCP port"
    echo "  ${CYAN}3)${RESET} ➖ Remove allowed TCP port"
    echo "  ${CYAN}4)${RESET} 📡 Show open ports (listening services)"
    echo "  ${CYAN}5)${RESET} 📜 Show allowed TCP ports in iptables"
    echo "  ${CYAN}6)${RESET} 🚫 Block an IP address"
    echo "  ${CYAN}7)${RESET} ✅ Unblock an IP address"
    echo "  ${CYAN}8)${RESET} 🔄 Reset firewall (clear all rules)"
    echo "  ${CYAN}9)${RESET} 🔥 Install PSAD + enable logging (no config changes)"
    echo "  ${CYAN}0)${RESET} ❎ Exit and close manager"
    echo "${MAGENTA}══════════════════════════════════════════════${RESET}"
    read -p "👉 Select an option: " choice

    case "$choice" in
        1) setup_firewall ;;
        2) add_port ;;
        3) remove_port ;;
        4) show_ports ;;
        5) show_iptables ;;
        6) block_ip ;;
        7) unblock_ip ;;
        8) reset_firewall ;;
        9) install_psad ;;
        0) echo "${BLUE}👋 Goodbye from LeoWall!${RESET}"; exit 0 ;;
        *) echo "${RED}❌ Invalid option. Please try again.${RESET}" ;;
    esac

    echo
    read -p "🔁 Press Enter to return to menu..."
done