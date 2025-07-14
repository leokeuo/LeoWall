# 🔥 LeoWall Firewall Manager

**LeoWall** is a simple and interactive bash-based firewall management script for Linux servers (Ubuntu/Debian), using `iptables` and enhanced with optional `psad` (Port Scan Attack Detector) integration.  
It's designed for sysadmins who want fast, secure, and visual control over TCP firewall rules, IP blocking, and basic security automation.

---

## ✨ Features

- 🎨 Visual logo and colorful terminal interface  
- 🔐 Configure firewall for selected TCP ports  
- ➕ Add or ➖ remove allowed TCP ports interactively  
- 📜 Show current iptables rules  
- 📡 View listening services on open ports  
- 🚫 Block or ✅ unblock any IP address  
- 🔄 Reset firewall (open all traffic)  
- 🔥 Install and activate `psad` to detect port scan attacks  
- 💾 Persistent firewall using `iptables-persistent`  

---

## 🧰 Requirements

- ✅ Debian-based system (Ubuntu, Debian)
- ✅ `bash`, `iptables`, `iptables-persistent`, `psad`
- ✅ Root or sudo privileges

---

## 🚀 Installation

Copy and run the following command:

```bash
git clone https://github.com/leokeuo/LeoWall.git && cd LeoWall && chmod +x leowall.sh && sudo ./leowall.sh
