#!/bin/bash
# ZIVPN UDP Server + CLI Menu + Network Optimization + Smart Auto-Kick
set -euo pipefail

B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Standalone CLI Menu + Network Optimization${Z}"
    echo -e "$LINE\n"
}
say 

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

wait_for_apt() {
  echo -e "${Y}⏳ apt ကို စောင့်နေပါသည်...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}

apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}

apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

echo -e "${Y}📦 Packages များ တင်သွင်းနေပါသည်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 iproute2 conntrack ca-certificates cron >/dev/null
apt_guard_end

systemctl stop zivpn.service 2>/dev/null || true

BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
mkdir -p /etc/zivpn

echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းလုဒ်ဆွဲနေပါသည်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

if [ ! -f "$CFG" ]; then
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=ZAW-VPN/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq '
    .auth.mode = "passwords" |
    .auth.config = [] |
    .listen = (."listen" // ":5667") |
    .cert = (."cert" // "/etc/zivpn/zivpn.crt") |
    .key  = (."key" // "/etc/zivpn/zivpn.key") |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# 🔴 DOMAIN သေချာမှတ်မည့်စနစ် 🔴
echo ""
echo -e "${C}────────────────────────────────────────────────────────${Z}"
echo -e "${Y}🌐 Domain ထည့်သွင်းလိုပါသလား? (Y/n)${Z}"
read -p "➔ ရွေးချယ်ရန်: " insert_domain
if [[ "${insert_domain,,}" == "y" || "${insert_domain,,}" == "yes" ]]; then
    read -p "➔ Domain ကို ရိုက်ထည့်ပါ (ဥပမာ - dtac.gamemobile.com): " raw_domain
    my_domain=$(echo "$raw_domain" | tr -d ' ' | tr -d '\r' | tr -d '\n')
    echo "$my_domain" > /etc/domain
    chmod 777 /etc/domain
    echo -e "${G}✅ Domain ($my_domain) ကို အောင်မြင်စွာ မှတ်သားပြီးပါပြီ!${Z}"
else
    echo "No-Domain" > /etc/domain
    chmod 777 /etc/domain
    echo -e "${Y}⚠️ Domain မထည့်သွင်းပါ။ Menu တွင် IP ကိုသာ ပြသပါမည်။${Z}"
fi
echo -e "${C}────────────────────────────────────────────────────────${Z}"
echo ""

cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo -e "${Y}🌐 UDP/DNAT + UFW + Network Optimization (TCP/UDP Tuning) ထည့်သွင်းနေပါသည်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
grep -q "^net.core.rmem_max" /etc/sysctl.conf || echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
grep -q "^net.core.wmem_max" /etc/sysctl.conf || echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf
grep -q "^net.core.rmem_default" /etc/sysctl.conf || echo "net.core.rmem_default=1048576" >> /etc/sysctl.conf
grep -q "^net.core.wmem_default" /etc/sysctl.conf || echo "net.core.wmem_default=1048576" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667

iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

echo -e "${Y}📋 CLI Menu ထည့်သွင်းနေပါသည်...${Z}"
wget -qO /usr/bin/menu "https://raw.githubusercontent.com/zaw-myscript/-my-zivpn/main/menu"
chmod +x /usr/bin/menu

# 🔴 SMART AUTO-KICK စနစ် 🔴
echo -e "${Y}⏱️ Smart Auto-Kick (အလိုအလျောက် သော့ပိတ်စနစ်) ထည့်သွင်းနေပါသည်...${Z}"
cat > /usr/local/bin/zivpn_autokick.sh << 'EOF'
#!/bin/bash
python3 -c "
import json, sys, os
from datetime import datetime
ufile = '/etc/zivpn/users.json'
cfile = '/etc/zivpn/config.json'
try:
    with open(ufile, 'r') as f: users = json.load(f)
except: sys.exit(0)
try:
    with open(cfile, 'r') as f: cfg = json.load(f)
except: cfg = {}

valid = set()
today = datetime.now().date()
for u in users:
    exp = u.get('expires')
    is_valid = True
    if exp:
        try:
            if datetime.strptime(exp.strip(), '%Y-%m-%d').date() < today: is_valid = False
        except: pass
    if is_valid and u.get('password'): valid.add(str(u['password']))

if 'auth' not in cfg or not type(cfg['auth']) is dict: cfg['auth'] = {}
current_config = cfg['auth'].get('config', [])
new_config = sorted(list(valid))

# ပြောင်းလဲမှုရှိမှသာ Update လုပ်ပြီး Restart ချရန် အချက်ပြမည်
if current_config != new_config:
    cfg['auth']['mode'] = 'passwords'
    cfg['auth']['config'] = new_config
    with open(cfile+'.tmp', 'w') as f: json.dump(cfg, f, indent=2)
    os.rename(cfile+'.tmp', cfile)
    sys.exit(1)
else:
    sys.exit(0)
"
# ပြောင်းလဲမှုရှိကြောင်း အချက်ပြမှသာ ZIVPN Service ကို Restart လုပ်ပါမည်
if [ $? -eq 1 ]; then
    systemctl restart zivpn.service > /dev/null 2>&1
fi
EOF
chmod +x /usr/local/bin/zivpn_autokick.sh
(crontab -l 2>/dev/null | grep -v "zivpn_autokick.sh" ; echo "0 * * * * /usr/local/bin/zivpn_autokick.sh") | crontab -
/usr/local/bin/zivpn_autokick.sh

systemctl daemon-reload
systemctl enable --now zivpn.service

echo -e "\n$LINE\n${G}✅ ZIVPN UDP Server နှင့် CLI Menu အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။${Z}"
echo -e "${C}အကောင့်စီမံရန် (Manage Accounts):${Z} ${Y}menu${Z} ${C}ဟု ရိုက်ထည့်ပါ။${Z}"
echo -e "$LINE"
