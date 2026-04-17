#!/bin/bash
# ZIVPN UDP Server + CLI Menu + Anti-Drop Network Optimization + DNS (No Auto-Kick)
set -euo pipefail

B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Anti-Drop Optimization + ZAWDNS${Z}"
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
apt-get install -y curl ufw jq python3 iproute2 conntrack ca-certificates >/dev/null
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

# 🔴 Auto-Kick အဟောင်းများကို လုံးဝ ရှင်းလင်းခြင်း 🔴
crontab -l 2>/dev/null | grep -v "zivpn_autokick.sh" | crontab - || true
rm -f /usr/local/bin/zivpn_autokick.sh

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
LimitNOFILE=655350
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo -e "${Y}🌐 UDP Anti-Drop + Network Optimization ထည့်သွင်းနေပါသည်...${Z}"
modprobe nf_conntrack >/dev/null 2>&1 || true

sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
sed -i '/nf_conntrack_udp_timeout/d' /etc/sysctl.conf
sed -i '/nf_conntrack_tcp_timeout_established/d' /etc/sysctl.conf

cat >> /etc/sysctl.conf << 'EOF'
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.netfilter.nf_conntrack_udp_timeout = 120
net.netfilter.nf_conntrack_udp_timeout_stream = 300
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
EOF
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

# 🔴 ZAWDNS ထည့်သွင်းခြင်း 🔴
echo -e "${Y}🚀 ZAWDNS (DNS Optimizer) ထည့်သွင်းနေပါသည်...${Z}"
cat > /usr/local/bin/zawdns << 'EOF'
#!/bin/bash
change_dns() {
    echo -e "\n\033[1;33m[*] DNS ကို $3 သို့ ပြောင်းလဲနေပါသည်...\033[0m"
    if [ -f /etc/systemd/resolved.conf ]; then
        sed -i '/^DNS=/d' /etc/systemd/resolved.conf 2>/dev/null
        echo "DNS=$1 $2" >> /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null
    fi
    rm -f /etc/resolv.conf
    echo "nameserver $1" > /etc/resolv.conf
    echo "nameserver $2" >> /etc/resolv.conf
    echo -e "\033[1;32m✅ အောင်မြင်ပါသည်။ ဆာဗာ၏ လမ်းကြောင်းကို $3 DNS သို့ ပြောင်းလဲပြီးပါပြီ!\033[0m"
    sleep 2
}
default_dns() {
    echo -e "\n\033[1;33m[*] မူလ Default DNS သို့ ပြန်လည်ပြောင်းလဲနေပါသည်...\033[0m"
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || echo "nameserver 8.8.8.8" > /etc/resolv.conf
    systemctl restart systemd-resolved 2>/dev/null
    echo -e "\033[1;32m✅ မူလအတိုင်း ပြန်ထားပြီးပါပြီ!\033[0m"
    sleep 2
}
while true; do
    clear
    echo -e "\033[1;32m          ZAW-VPN NETWORK & DNS OPTIMIZER (PRO)              \033[0m"
    echo -e "\033[1;35m==============================================================\033[0m"
    echo -e " \033[1;36mသင့်ဆာဗာလိုင်းကို အငြိမ်ဆုံးဖြစ်အောင် အောက်ပါ DNS များ ရွေးချယ်နိုင်သည်\033[0m\n"
    echo -e "   \033[1;33m[1]\033[0m 🚀 Cloudflare DNS \033[1;36m(1.1.1.1)\033[0m  - \033[1;32mဂိမ်းဆော့/လိုင်းဖောက်ရန် အငြိမ်ဆုံး\033[0m"
    echo -e "   \033[1;33m[2]\033[0m 🌐 Google DNS     \033[1;36m(8.8.8.8)\033[0m  - \033[1;32mလူသုံးအများဆုံးနှင့် ယုံကြည်ရဆုံး\033[0m"
    echo -e "   \033[1;33m[3]\033[0m 🛡️ AdGuard DNS    \033[1;36m(94.140.x)\033[0m - \033[1;32mကြော်ငြာများကို အလိုအလျောက်ပိတ်ရန်\033[0m"
    echo -e "   \033[1;33m[4]\033[0m 🔄 မူလ DNS သို့ ပြန်ထားရန်     - \033[1;32mDefault သို့ပြန်သွားရန်\033[0m"
    echo -e "   \033[1;33m[0]\033[0m ❌ ထွက်မည် \033[1;31m(Exit)\033[0m"
    echo -e "\033[1;35m==============================================================\033[0m"
    read -p " နှိပ်လိုသော နံပါတ်ကို ရွေးချယ်ပါ (0-4): " option
    case $option in
        1) change_dns "1.1.1.1" "1.0.0.1" "Cloudflare" ;;
        2) change_dns "8.8.8.8" "8.8.4.4" "Google" ;;
        3) change_dns "94.140.14.14" "94.140.15.15" "AdGuard" ;;
        4) default_dns ;;
        0) echo -e "\033[1;32mကျေးဇူးတင်ပါသည် ZAW-VPN ကို အသုံးပြုတဲ့အတွက်!\033[0m"; break ;;
        *) echo -e "\033[1;31m❌ နံပါတ်မှားယွင်းနေပါသည်။ ပြန်ရွေးချယ်ပါ။\033[0m"; sleep 1 ;;
    esac
done
EOF
chmod +x /usr/local/bin/zawdns

# 🔴 AUTO-DETECT: SSH Script အဟောင်းရှိ/မရှိ အလိုလို စစ်ဆေးပေးမည့်စနစ် 🔴
echo -e "${Y}📋 CLI Menu ထည့်သွင်းနေပါသည်...${Z}"
if [ -f "/bin/menu" ] || [ -f "/usr/local/bin/menu" ]; then
    wget -qO /usr/bin/zmenu "https://raw.githubusercontent.com/zaw-myscript/-my-zivpn/main/menu"
    chmod +x /usr/bin/zmenu
    MENU_CMD="zmenu"
else
    wget -qO /usr/bin/menu "https://raw.githubusercontent.com/zaw-myscript/-my-zivpn/main/menu"
    chmod +x /usr/bin/menu
    MENU_CMD="menu"
fi

systemctl daemon-reload
systemctl enable --now zivpn.service

echo -e "\n$LINE\n${G}✅ ZIVPN UDP Server နှင့် CLI Menu အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။${Z}"
echo -e "${C}အကောင့်စီမံရန် (Manage Accounts):${Z} ${Y}${MENU_CMD}${Z} ${C}ဟု ရိုက်ထည့်ပါ။${Z}"
echo -e "${C}DNS ပြောင်းရန် (Change DNS):${Z} ${Y}zawdns${Z} ${C}ဟု ရိုက်ထည့်ပါ။${Z}"
echo -e "$LINE"
