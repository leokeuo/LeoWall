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

show_tip() {
    echo
    echo -n "${YELLOW}💡 Tip: You can run this script anytime via: ${GREEN}sudo leowall"
    sleep 1
    echo -n "."
    sleep 1
    echo -n "."
    sleep 1
    echo -e ".${RESET}"
    sleep 1
    echo
}

# ========== INSTALL TO /usr/local/bin ==========
install_to_bin() {
    cp "$0" /usr/local/bin/leowall
    chmod +x /usr/local/bin/leowall
}

# ========== PSAD INSTALL ==========
install_psad() {
    show_logo
    echo "${BLUE}📦 Installing psad...${RESET}"
    sudo apt update
    sudo apt install -y psad iptables-persistent
    sudo iptables -A INPUT -j LOG --log-prefix "PSAD: " --log-level 4
    sudo psad --sig-update
    sudo psad -R
    sudo psad -H
    sudo systemctl restart psad
    sudo systemctl enable psad
    echo "${GREEN}✅ PSAD installed and logging enabled.${RESET}"
}

# ========== FIREWALL SETUP ==========
setup_firewall() {
    show_logo
    echo "${YELLOW}💬 Enter allowed TCP ports (space-separated)."
    echo "ℹ️ SSH (22) will be allowed by default.${RESET}"
    read -p "✅ TCP Ports: " -a TCP_USER

    echo "${YELLOW}💬 Enter allowed UDP ports (space-separated), or leave blank for none.${RESET}"
    read -p "✅ UDP Ports: " -a UDP_USER

    TCP_OPEN=(22 "${TCP_USER[@]}")
    UDP_OPEN=("${UDP_USER[@]}")

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
    for port in "${TCP_OPEN[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        echo "   → TCP port ${GREEN}$port${RESET} allowed"
    done

    if [[ ${#UDP_OPEN[@]} -gt 0 ]]; then
        echo "${GREEN}✅ Opening UDP ports:${RESET}"
        for port in "${UDP_OPEN[@]}"; do
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
            echo "   → UDP port ${GREEN}$port${RESET} allowed"
        done
    fi

    iptables -A INPUT -p udp -j DROP

    iptables-save > /etc/iptables/rules.v4
    echo "${GREEN}✅ Rules saved and UDP restricted.${RESET}"
}

# ========== OTHER ACTIONS ==========
add_port() {
    show_logo
    read -p "➕ Enter protocol (tcp/udp): " proto
    read -p "➕ Enter port to allow: " port
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$proto" =~ ^(tcp|udp)$ ]]; then
        iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || {
            iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
            iptables-save > /etc/iptables/rules.v4
            echo "${GREEN}✔️ $proto port $port allowed.${RESET}"
        }
    else
        echo "${RED}❌ Invalid input.${RESET}"
    fi
}

remove_port() {
    show_logo
    read -p "➖ Enter protocol (tcp/udp): " proto
    read -p "➖ Enter port to remove: " port
    iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    iptables-save > /etc/iptables/rules.v4
    echo "${GREEN}✔️ $proto port $port removed.${RESET}"
}

reset_firewall() {
    show_logo
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
    echo "${GREEN}✅ Firewall reset. All traffic allowed.${RESET}"
}

show_ports() {
    show_logo
    echo "${CYAN}🔍 Real accessible open ports (LISTEN + reachable):${RESET}"
    ss -tuln | grep -E 'LISTEN|UNCONN' | grep -v 127.0.0.1 | grep -v '\[::1\]' || echo "${YELLOW}⚠️ No reachable open ports found.${RESET}"
}

show_iptables() {
    show_logo
    echo "${CYAN}📜 Current allowed ports:${RESET}"
    iptables -S | grep -- '--dport' || echo "${YELLOW}⚠️ No ports allowed yet.${RESET}"
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
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    iptables-save > /etc/iptables/rules.v4
    echo "${GREEN}✔️ Unblocked IP: $ip${RESET}"
}

# ========== MAIN ==========
install_to_bin
show_logo
show_tip

while true; do
    echo "${MAGENTA}${BOLD}📋 MAIN MENU:${RESET}"
    echo "${MAGENTA}══════════════════════════════════════════════${RESET}"
    echo "  ${CYAN}1)${RESET} 🔐 Set up firewall (TCP & UDP)"
    echo "  ${CYAN}2)${RESET} ➕ Add allowed port (tcp/udp)"
    echo "  ${CYAN}3)${RESET} ➖ Remove allowed port (tcp/udp)"
    echo "  ${CYAN}4)${RESET} 📡 Show real open ports"
    echo "  ${CYAN}5)${RESET} 📜 Show iptables rules"
    echo "  ${CYAN}6)${RESET} 🚫 Block an IP"
    echo "  ${CYAN}7)${RESET} ✅ Unblock an IP"
    echo "  ${CYAN}8)${RESET} 🔄 Reset firewall"
    echo "  ${CYAN}9)${RESET} 🔥 Install PSAD (no config changes)"
    echo "  ${CYAN}0)${RESET} ❎ Exit"
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
        *) echo "${RED}❌ Invalid option. Try again.${RESET}" ;;
    esac
    echo
    read -p "🔁 Press Enter to return to menu..."
done
