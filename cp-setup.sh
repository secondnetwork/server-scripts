#!/bin/bash

# ==========================================
# Fail2Ban Auto-Setup für CloudPanel (Nginx)
# Version: 1.3 (Expanded: User + Global Logs)
# ==========================================

# Farben für Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starte Fail2Ban Installation & Konfiguration ===${NC}"

# 1. Root-Rechte prüfen
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Fehler: Bitte als Root ausführen (sudo).${NC}"
  exit 1
fi

# 2. Installation
echo -e "${GREEN}[1/5] Installiere notwendige Pakete...${NC}"
apt-get update -qq
apt-get install -y fail2ban iptables -qq

# 3. Filter Definition
echo -e "${GREEN}[2/5] Erstelle Filter-Regeln (cloudpanel-dos.conf)...${NC}"
cat <<EOF > /etc/fail2ban/filter.d/nginx-cloudpanel-dos.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*\.(env|git|yml|sql|bak|swp|config|ini|php|json|sh|yaml|xmlrpc\.php).*" .*$
            ^<HOST> -.*"(GET|POST|HEAD) /.*wp-admin.*" (404|403|444) .*$
            ^<HOST> -.*"(GET|POST|HEAD) /.*blog-verify.*" (404|403|444) .*$
        

ignoreregex = .*\.(jpg|jpeg|png|gif|css|js|svg|xml|txt).*
# Hier kannst du bei Bedarf Google Bots ausschließen, falls nötig
# .*Googlebot.*
EOF

# 4. Jail Konfiguration
echo -e "${GREEN}[3/5] Konfiguriere Jail (Jail.local)...${NC}"
cat <<EOF > /etc/fail2ban/jail.d/nginx-cloudpanel.conf
[nginx-cloudpanel-dos]
enabled  = true
# WICHTIG: 'auto' verhindert Warnungen bzgl. systemd/journalmatch und nutzt Datei-Polling
backend  = auto
port     = http,https
filter   = nginx-cloudpanel-dos
# Wildcard * findet alle CloudPanel User Logs UND das globale Log
logpath  = /home/*/logs/nginx/access.log
           /var/log/nginx/access.log
maxretry = 15
findtime = 25
bantime  = 3600
# Falls du jemals die Ban-Zeit erhöhen willst:
# bantime = 86400  ; 1 Tag
# bantime = 604800 ; 1 Woche

action   = iptables-multiport[name=NoDos, port="http,https"]
EOF

# 5. Service aktivieren und starten
echo -e "${GREEN}[4/5] Aktiviere Autostart und lade Dienste neu...${NC}"
systemctl enable fail2ban
systemctl restart fail2ban

# Kurze Pause
sleep 2

# 6. Status-Check
echo -e "${GREEN}[5/5] Statusprüfung...${NC}"

if systemctl is-active --quiet fail2ban; then
    JAIL_STATUS=$(fail2ban-client status nginx-cloudpanel-dos)
    echo -e "${GREEN}✓ Fail2Ban läuft und ist beim Boot aktiviert.${NC}"
    echo -e "${BLUE}Aktueller Jail Status:${NC}"
    echo "$JAIL_STATUS" | grep "File list" -A 10
else
    echo -e "${RED}X Fehler: Fail2Ban läuft nicht. Prüfe: journalctl -u fail2ban${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=== Installation Abgeschlossen ===${NC}"
echo -e "Befehle für die Zukunft:"
echo -e "Status sehen:    ${GREEN}fail2ban-client status nginx-cloudpanel-dos${NC}"
echo -e "IP entbannen:    ${GREEN}fail2ban-client set nginx-cloudpanel-dos unbanip <IP>${NC}"
echo -e "Logs live sehen: ${GREEN}tail -f /var/log/fail2ban.log${NC}"
