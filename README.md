✅ README.md – LeoWall Firewall Manager

🔥 LeoWall Firewall Manager

LeoWall is a simple and interactive bash-based firewall management script for Linux servers (Ubuntu/Debian), using iptables and enhanced with psad (Port Scan Attack Detector) integration.
Designed for sysadmins who want fast and clear control over their TCP firewall rules, IP blocking, and basic security automation.

✨ Features

✅ Visual logo and colorful interface
🔐 Configure firewall for selected TCP ports
➕ Add or ➖ remove allowed TCP ports interactively
📜 Show current iptables rules
📡 View listening services on open ports
🚫 Block or ✅ unblock any IP address
🔄 Reset firewall (open all traffic)
🔥 Install and activate psad to detect port scan attacks
💾 Persistent firewall using iptables-persistent
🧰 Requirements

Debian-based systems (Ubuntu, Debian)
bash, iptables, iptables-persistent, psad
Root or sudo privileges
🚀 Installation

## 🔥 LeoWall Installation

To quickly install LeoWall, run the following:

```bash
git clone https://github.com/leokeuo/LeoWall.git && cd LeoWall && chmod +x leowall.sh && sudo ./leowall.sh


🧑‍💻 Usage

After launching the script, use the menu to manage your firewall:

📋 MAIN MENU:
════════════════════════════════════════════════════
  1) 🔐 Set up firewall (allow selected TCP ports)
  2) ➕ Add a new allowed TCP port
  3) ➖ Remove allowed TCP port
  4) 📡 Show open ports (listening services)
  5) 📜 Show allowed TCP ports in iptables
  6) 🚫 Block an IP address
  7) ✅ Unblock an IP address
  8) 🔄 Reset firewall (clear all rules)
  9) 🔥 Install PSAD + enable logging (no config changes)
  0) ❎ Exit and close manager

  ⚠️ Notes
	•	SSH Port (22) is always allowed by default to prevent locking yourself out.
	•	psad integration only adds the required iptables log rule. It does not modify your /etc/psad/psad.conf.
	•	iptables-persistent ensures all rules survive reboot.

⸻

🧠 Future Plans
	•	Add UDP port support
	•	Export firewall rules to a backup file
	•	Generate security reports
	•	Convert to systemd service
