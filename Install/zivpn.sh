#!/bin/bash
# ZIVPN UDP Server + Cyberpunk Web UI + Network Optimization (All-in-One with Copy Feature)
set -euo pipefail

B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + ZAWVPN PRO (Cyberpunk UI) + Network Optimization${Z}"
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
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
TEMPLATES_DIR="/etc/zivpn/templates" 
mkdir -p /etc/zivpn "$TEMPLATES_DIR" 

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

echo -e "${G}🔒 Web Admin Login UI ထည့်သွင်းခြင်း${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  read -r -p "Contact Link (ဥပမာ: https://m.me/yourname or Enter=disable): " CONTACT_LINK
  
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY_SECRET'
import secrets;print(secrets.token_hex(32))
PY_SECRET
)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
    echo "WEB_CONTACT_LINK=${CONTACT_LINK:-}" 
  } > "$ENVF"
  chmod 600 "$ENVF"
  echo -e "${G}✅ Web login UI ဖွင့်ထားပါသည်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
fi

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲပါ) eg: ZAW1,ZAW2${Z}"
read -r -p "Passwords (Enter=zaw): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zaw"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = (."cert" // "/etc/zivpn/zivpn.crt") |
    .key  = (."key" // "/etc/zivpn/zivpn.key") |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

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

echo -e "${Y}📄 Cyberpunk UI (Cards Design) ထည့်သွင်းနေပါသည်...${Z}"
cat >"$TEMPLATES_DIR/users_table_wrapper.html" <<'WRAPPER_HTML'
<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZAWVPN Pro - Users List</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;800&display=swap');
:root { --bg: #050505; --card-bg: rgba(20, 20, 20, 0.8); --primary: #00ffcc; --primary-glow: rgba(0, 255, 204, 0.4); --text: #f0f0f0; --text-muted: #888; --danger: #ff3366; --warning: #ffcc00; --border: rgba(255,255,255,0.1); }
* { box-sizing: border-box; font-family: 'Poppins', sans-serif; }
body { background: var(--bg); color: var(--text); margin: 0; padding: 0; padding-bottom: 80px; min-height: 100vh; background-image: radial-gradient(circle at 50% 0%, #1a2a2a 0%, #050505 50%); }
.header { background: rgba(0,0,0,0.5); backdrop-filter: blur(10px); padding: 15px 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: center; position: sticky; top: 0; z-index: 100; box-shadow: 0 4px 30px rgba(0,0,0,0.5); }
.header h1 { margin: 0; font-size: 1.5rem; font-weight: 800; color: var(--text); letter-spacing: 2px; }
.header h1 span { color: var(--primary); text-shadow: 0 0 10px var(--primary-glow); }
.container { max-width: 800px; margin: 20px auto; padding: 0 15px; }

.cards-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 15px; }
.user-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 16px; padding: 20px; backdrop-filter: blur(10px); box-shadow: 0 5px 20px rgba(0,0,0,0.5); transition: 0.3s; position: relative; overflow: hidden; }
.user-card:hover { transform: translateY(-5px); border-color: var(--primary-glow); box-shadow: 0 10px 30px var(--primary-glow); }
.user-card::before { content: ''; position: absolute; top: 0; left: 0; width: 4px; height: 100%; background: var(--primary); box-shadow: 0 0 10px var(--primary); }
.user-card.expiring::before { background: var(--warning); box-shadow: 0 0 10px var(--warning); }
.user-card.expired { opacity: 0.6; }
.user-card.expired::before { background: var(--danger); box-shadow: 0 0 10px var(--danger); }

.card-header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border); padding-bottom: 10px; margin-bottom: 15px; }
.card-header h3 { margin: 0; color: #fff; font-size: 1.2rem; display: flex; align-items: center; gap: 8px;}
.badge { padding: 4px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; }
.badge.active { background: rgba(0,255,204,0.1); color: var(--primary); border: 1px solid var(--primary-glow); }
.badge.warning { background: rgba(255,204,0,0.1); color: var(--warning); border: 1px solid rgba(255,204,0,0.4); }
.badge.danger { background: rgba(255,51,102,0.1); color: var(--danger); border: 1px solid rgba(255,51,102,0.4); }

.card-body p { margin: 8px 0; color: var(--text-muted); font-size: 0.95rem; display: flex; align-items: center; gap: 10px; }
.card-body p span { color: var(--text); font-weight: 600; font-family: monospace; font-size: 1.1rem; }

.card-actions { display: flex; gap: 10px; margin-top: 15px; }
.card-actions button { flex: 1; padding: 10px; border-radius: 8px; border: none; font-weight: 600; cursor: pointer; transition: 0.3s; display: flex; justify-content: center; align-items: center; gap: 5px;}
.btn-edit { background: rgba(255,255,255,0.1); color: #fff; }
.btn-edit:hover { background: var(--primary); color: #000; }
.btn-del { background: rgba(255,51,102,0.1); color: var(--danger); }
.btn-del:hover { background: var(--danger); color: #fff; }
.del-form { flex: 1; display: flex; margin: 0; }
.del-form button { width: 100%; }

.bottom-nav { position: fixed; bottom: 0; left: 0; width: 100%; background: rgba(10,10,10,0.9); backdrop-filter: blur(15px); border-top: 1px solid var(--border); display: flex; justify-content: space-around; padding: 10px 0; z-index: 100; }
.bottom-nav a { color: var(--text-muted); text-decoration: none; display: flex; flex-direction: column; align-items: center; font-size: 0.75rem; gap: 5px; transition: 0.3s; }
.bottom-nav a i { font-size: 1.5rem; font-style: normal; filter: grayscale(100%); transition: 0.3s; }
.bottom-nav a.active { color: var(--primary); }
.bottom-nav a.active i { filter: grayscale(0%) drop-shadow(0 0 5px var(--primary-glow)); transform: translateY(-3px); }

.modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); backdrop-filter: blur(5px); z-index: 2000; align-items: center; justify-content: center; }
.modal-content { background: var(--bg); border: 1px solid var(--primary-glow); border-radius: 16px; padding: 25px; width: 90%; max-width: 400px; box-shadow: 0 10px 50px rgba(0,255,204,0.2); position: relative; }
.close-btn { position: absolute; right: 20px; top: 15px; font-size: 1.5rem; color: var(--text-muted); cursor: pointer; }
.modal input { width: 100%; background: rgba(255,255,255,0.05); border: 1px solid var(--border); padding: 12px; border-radius: 8px; color: #fff; margin-bottom: 15px; font-size: 1rem; outline: none; }
.modal input:focus { border-color: var(--primary); }
.modal button.save-btn { width: 100%; background: var(--primary); color: #000; font-weight: 800; padding: 12px; border: none; border-radius: 8px; cursor: pointer; text-transform: uppercase; }
</style>
</head><body>
<div class="header"><h1>ZAW<span>VPN</span> PRO</h1></div>

<div class="container">
    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
        <h2 style="margin:0;">Members List</h2>
    </div>

    <div class="cards-grid">
        {% for u in users %}
        <div class="user-card {% if u.expires_date and u.expires_date < today_date %}expired{% elif u.expiring_soon %}expiring{% endif %}">
            <div class="card-header">
                <h3><i style="font-style:normal;">👤</i> {{u.user}}</h3>
                {% if u.expires_date and u.expires_date < today_date %}
                    <span class="badge danger">Expired</span>
                {% elif u.expiring_soon %}
                    <span class="badge warning">Expiring</span>
                {% else %}
                    <span class="badge active">Active</span>
                {% endif %}
            </div>
            <div class="card-body">
                <p><i style="font-style:normal;">🔑</i> Password: <span>{{u.password}}</span></p>
                <p><i style="font-style:normal;">📅</i> Expires: 
                    <span>
                    {% if u.expires %}
                        {{u.expires}} 
                        <small style="color:var(--text-muted); font-size:0.8rem; font-family:'Poppins',sans-serif;">
                        {% if u.days_remaining is not none %}
                            {% if u.days_remaining == 0 %} (Today) {% else %} ({{u.days_remaining}}d left) {% endif %}
                        {% endif %}
                        </small>
                    {% else %} Never {% endif %}
                    </span>
                </p>
            </div>
            <div class="card-actions">
                <button class="btn-edit" onclick="showEdit('{{u.user}}','{{u.password}}','{{u.expires}}')"><i>✏️</i> Edit</button>
                <form class="del-form" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်ရန် သေချာပါသလား?')">
                    <input type="hidden" name="user" value="{{u.user}}">
                    <button type="submit" class="btn-del"><i>🗑️</i> Delete</button>
                </form>
            </div>
        </div>
        {% endfor %}
    </div>
</div>

<div id="editModal" class="modal">
  <div class="modal-content">
    <span class="close-btn" onclick="document.getElementById('editModal').style.display='none'">&times;</span>
    <h3 style="margin-top:0; color:var(--primary);"><i style="font-style:normal;">✏️</i> Edit Account</h3>
    <form method="post" action="/edit">
        <input type="hidden" id="edit-user" name="user">
        <label style="font-size:0.85rem; color:var(--text-muted);">Username</label>
        <input type="text" id="display-user" readonly style="opacity:0.6; cursor:not-allowed;">
        <label style="font-size:0.85rem; color:var(--text-muted);">New Password</label>
        <input type="text" id="edit-pass" name="password" required>
        <label style="font-size:0.85rem; color:var(--text-muted);">New Expiry (Date or Days)</label>
        <input type="text" id="edit-exp" name="expires" required>
        <button class="save-btn" type="submit">SAVE CHANGES</button>
    </form>
  </div>
</div>

<div class="bottom-nav">
    <a href="/"><i>➕</i><span>Create</span></a>
    <a href="/users" class="active"><i>👥</i><span>Users List</span></a>
    <a href="/logout"><i>🚪</i><span>Logout</span></a>
</div>

<script>
function showEdit(u, p, e) {
    document.getElementById('edit-user').value = u;
    document.getElementById('display-user').value = u;
    document.getElementById('edit-pass').value = p;
    document.getElementById('edit-exp').value = e;
    document.getElementById('editModal').style.display = 'flex';
}
window.onclick = function(e) {
    if (e.target == document.getElementById('editModal')) document.getElementById('editModal').style.display = 'none';
}
</script>
</body></html>
WRAPPER_HTML

cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta, date

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://zivpn-web.free.nf/zivpn-icon.png"

def get_server_ip():
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        ip = result.stdout.strip().split()[0]
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip): return ip
    except: pass
    return "127.0.0.1" 

SERVER_IP_FALLBACK = get_server_ip()
CONTACT_LINK = os.environ.get("WEB_CONTACT_LINK", "").strip()

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZAWVPN Pro Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;800&display=swap');
:root { --bg: #050505; --card-bg: rgba(20, 20, 20, 0.8); --primary: #00ffcc; --primary-glow: rgba(0, 255, 204, 0.4); --text: #f0f0f0; --text-muted: #888; --danger: #ff3366; --border: rgba(255,255,255,0.1); }
* { box-sizing: border-box; font-family: 'Poppins', sans-serif; }
body { background: var(--bg); color: var(--text); margin: 0; padding: 0; padding-bottom: 80px; min-height: 100vh; background-image: radial-gradient(circle at 50% 0%, #1a2a2a 0%, #050505 50%); }
.header { background: rgba(0,0,0,0.5); backdrop-filter: blur(10px); padding: 15px 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: center; position: sticky; top: 0; z-index: 100; box-shadow: 0 4px 30px rgba(0,0,0,0.5); }
.header h1 { margin: 0; font-size: 1.5rem; font-weight: 800; color: var(--text); letter-spacing: 2px; }
.header h1 span { color: var(--primary); text-shadow: 0 0 10px var(--primary-glow); }
.container { max-width: 500px; margin: 30px auto; padding: 0 20px; }
.glass-panel { background: var(--card-bg); border: 1px solid var(--border); border-radius: 16px; padding: 25px; backdrop-filter: blur(10px); box-shadow: 0 10px 40px rgba(0,0,0,0.6); }
.stats-card { background: linear-gradient(135deg, rgba(0,255,204,0.1) 0%, rgba(0,0,0,0) 100%); border: 1px solid var(--primary-glow); text-align: center; margin-bottom: 25px; }
.stats-card h2 { margin: 0; font-size: 2.5rem; color: var(--primary); text-shadow: 0 0 15px var(--primary-glow); }
.stats-card p { margin: 5px 0 0; color: var(--text-muted); font-size: 0.9rem; text-transform: uppercase; letter-spacing: 1px;}
.input-group { margin-bottom: 20px; position: relative; }
.input-group input { width: 100%; background: rgba(0,0,0,0.4); border: 1px solid var(--border); border-radius: 10px; padding: 15px 15px 15px 45px; color: var(--text); font-size: 1rem; transition: all 0.3s ease; outline: none; }
.input-group input:focus { border-color: var(--primary); box-shadow: 0 0 15px var(--primary-glow); }
.input-group i { position: absolute; left: 15px; top: 16px; font-style: normal; font-size: 1.2rem; opacity: 0.7; }
.btn { width: 100%; background: var(--primary); color: #000; font-weight: 800; border: none; padding: 15px; border-radius: 10px; font-size: 1.1rem; cursor: pointer; transition: all 0.3s; text-transform: uppercase; letter-spacing: 1px; box-shadow: 0 0 15px var(--primary-glow); }
.btn:hover { transform: translateY(-2px); box-shadow: 0 0 25px var(--primary-glow); background: #33ffdb; }
.bottom-nav { position: fixed; bottom: 0; left: 0; width: 100%; background: rgba(10,10,10,0.9); backdrop-filter: blur(15px); border-top: 1px solid var(--border); display: flex; justify-content: space-around; padding: 10px 0; z-index: 100; }
.bottom-nav a { color: var(--text-muted); text-decoration: none; display: flex; flex-direction: column; align-items: center; font-size: 0.75rem; gap: 5px; transition: 0.3s; }
.bottom-nav a i { font-size: 1.5rem; font-style: normal; filter: grayscale(100%); transition: 0.3s; }
.bottom-nav a.active { color: var(--primary); }
.bottom-nav a.active i { filter: grayscale(0%) drop-shadow(0 0 5px var(--primary-glow)); transform: translateY(-3px); }
.msg { padding: 15px; border-radius: 10px; margin-bottom: 20px; font-size: 0.9rem; border: 1px solid; }
.msg.err { background: rgba(255,51,102,0.1); color: var(--danger); border-color: rgba(255,51,102,0.3); }

/* 💡 Copy Card CSS Additions */
.user-info-card { position: fixed; top: 20px; left: 50%; transform: translateX(-50%); background: rgba(0, 255, 204, 0.1); color: var(--text); border: 1px solid var(--primary-glow); border-radius: 12px; padding: 20px; box-shadow: 0 10px 40px rgba(0,255,204,0.3); z-index: 2000; width: 90%; max-width: 350px; backdrop-filter: blur(10px); }
.user-info-card h4 { margin-top: 0; color: var(--primary); font-size: 1.1rem; margin-bottom: 10px; text-shadow: 0 0 5px var(--primary-glow); }
.user-info-card p { margin: 8px 0; font-size: 0.95rem; }
.user-info-card b { color: #fff; font-family: monospace; font-size: 1.05rem; }
.copy-btn { margin-top: 15px; width: 100%; padding: 10px; background: rgba(255,255,255,0.1); border: 1px solid var(--border); color: #fff; border-radius: 8px; cursor: pointer; transition: 0.3s; font-weight: 600; }
.copy-btn:hover { background: var(--primary); color: #000; box-shadow: 0 0 15px var(--primary-glow); }
</style>
</head><body>
<div class="header"><h1>ZAW<span>VPN</span> PRO</h1></div>
<div class="container">
{% if not authed %}
    <div class="glass-panel" style="text-align: center; margin-top: 50px;">
        <img src="{{logo}}" style="width: 80px; border-radius: 50%; border: 2px solid var(--primary); box-shadow: 0 0 20px var(--primary-glow); margin-bottom: 20px;">
        <h2 style="margin-top:0;">Admin Login</h2>
        {% if err %}<div class="msg err">{{err}}</div>{% endif %}
        <form action="/login" method="POST">
            <div class="input-group"><i>👤</i><input type="text" name="u" placeholder="Username" required></div>
            <div class="input-group"><i>🔑</i><input type="password" name="p" placeholder="Password" required></div>
            <button class="btn" type="submit">LOGIN TO PANEL</button>
        </form>
        {% if contact_link %}
        <div style="margin-top:20px;">
            <a href="{{ contact_link }}" target="_blank" style="color:var(--primary); text-decoration:none; font-size:0.95rem;"><i>🗨️</i> ဆက်သွယ်ရန် / Contact Admin</a>
        </div>
        {% endif %}
    </div>
{% else %}
    <div class="glass-panel stats-card">
        <h2>{{ total_users }}</h2>
        <p>Active Users Online</p>
    </div>
    {% if err %}<div class="msg err">{{err}}</div>{% endif %}
    
    <script>
        {% if msg and '{' in msg and '}' in msg %}
        try {
            const data = JSON.parse('{{ msg | safe }}');
            if (data.user) {
                const card = document.createElement('div');
                card.className = 'user-info-card';
                card.innerHTML = `
                    <h4>✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ</h4>
                    <p>🔥 Server IP: <b style="color:var(--primary);">${data.ip || '{{ IP }}'}</b></p>
                    <p>👤 Username: <b>${data.user}</b></p>
                    <p>🔑 Password: <b>${data.password}</b></p>
                    <p>⏰ Expires: <b>${data.expires || 'N/A'}</b></p>
                    <button class="copy-btn" onclick="copyDetails()">📋 Copy အချက်အလက်များ</button>
                `;
                document.body.appendChild(card);
                
                window.copyDetails = function() {
                    const text = `✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ\n🔥 Server IP: ${data.ip || '{{ IP }}'}\n👤 Username: ${data.user}\n🔑 Password: ${data.password}\n⏰ Expires: ${data.expires || 'N/A'}`;
                    navigator.clipboard.writeText(text).then(() => {
                        const btn = card.querySelector('.copy-btn');
                        btn.innerHTML = '✅ Copied!';
                        btn.style.background = 'var(--primary)';
                        btn.style.color = '#000';
                        setTimeout(() => { if(card.parentNode) card.parentNode.removeChild(card); }, 2500);
                    }).catch(err => alert("Copy error!"));
                };
            }
        } catch (e) { console.error("Error parsing message JSON:", e); }
        {% endif %}
    </script>
    
    <div class="glass-panel">
        <h3 style="margin-top:0; border-bottom: 1px solid var(--border); padding-bottom: 10px;"><i style="font-style:normal;">➕</i> Create New Account</h3>
        <form action="/add" method="POST">
            <div class="input-group"><i>👤</i><input type="text" name="user" placeholder="Username" required></div>
            <div class="input-group"><i>🔑</i><input type="password" name="password" placeholder="Password" required></div>
            <div class="input-group"><i>📅</i><input type="text" name="expires" placeholder="Days (e.g. 30) or YYYY-MM-DD" required></div>
            <div class="input-group"><i>📡</i><input type="text" name="ip" value="{{ IP }}" readonly style="color:var(--primary); font-weight:bold;"></div>
            <button class="btn" type="submit">CREATE ACCOUNT</button>
        </form>
    </div>
    <div class="bottom-nav">
        <a href="/" class="active"><i>➕</i><span>Create</span></a>
        <a href="/users"><i>👥</i><span>Users List</span></a>
        <a href="/logout"><i>🚪</i><span>Logout</span></a>
    </div>
{% endif %}
</div></body></html>"""

app = Flask(__name__, template_folder="/etc/zivpn/templates")
app.secret_key = os.environ.get("WEB_SECRET","dev-secret")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","M-69P").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","M-69P").strip()

def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except: return default
def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass
def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v: out.append({"user":u.get("user",""), "password":u.get("password",""), "expires":u.get("expires","")})
  return out
def save_users(users): write_json_atomic(USERS_FILE, users)

def get_total_active_users():
    users = load_users(); active = 0
    for u in users:
        exp = u.get("expires")
        if exp:
            try:
                if datetime.strptime(exp, "%Y-%m-%d").date() >= date.today(): active += 1
            except: active += 1
        else: active += 1
    return active

def is_expiring_soon(expires_str):
    if not expires_str: return False
    try:
        rem = (datetime.strptime(expires_str, "%Y-%m-%d").date() - date.today()).days
        return 0 <= rem <= 1
    except: return False
    
def calculate_days_remaining(expires_str):
    if not expires_str: return None
    try:
        rem = (datetime.strptime(expires_str, "%Y-%m-%d").date() - date.today()).days
        return rem if rem >= 0 else None
    except: return None
    
def delete_user(user):
    users = [u for u in load_users() if u.get("user").lower() != user.lower()]
    save_users(users); sync_config_passwords()
    
def check_user_expiration():
    users = load_users(); keep = []; deleted = 0
    for u in users:
        exp = u.get("expires"); expired = False
        if exp:
            try:
                if datetime.strptime(exp, "%Y-%m-%d").date() < date.today(): expired = True
            except: pass
        if expired: deleted += 1
        else: keep.append(u)
    if deleted > 0: save_users(keep); sync_config_passwords(); return True 
    return False 

def sync_config_passwords():
  cfg=read_json(CONFIG_FILE,{}); users=load_users(); valid = set()
  for u in users:
      exp = u.get("expires"); is_valid = True
      if exp:
          try:
              if datetime.strptime(exp, "%Y-%m-%d").date() < date.today(): is_valid = False
          except: pass
      if is_valid and u.get("password"): valid.add(str(u["password"]))
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"; cfg["auth"]["config"]=sorted(list(valid))
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)

def require_login(): return bool(ADMIN_USER and ADMIN_PASS) and session.get("auth") != True

def prepare_user_data():
    check_user_expiration() 
    view=[]
    for u in load_users():
      exp_obj = None
      if u.get("expires"):
          try: exp_obj = datetime.strptime(u.get("expires"), "%Y-%m-%d").date()
          except: pass
      view.append(type("U",(),{
        "user":u.get("user",""), "password":u.get("password",""), "expires":u.get("expires",""),
        "expires_date": exp_obj, "days_remaining": calculate_days_remaining(u.get("expires","")),
        "expiring_soon": is_expiring_soon(u.get("expires","")) 
      }))
    view.sort(key=lambda x:(x.user or "").lower())
    return view, datetime.now().strftime("%Y-%m-%d"), date.today()

@app.route("/", methods=["GET"])
def index(): 
    if require_login(): return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), contact_link=CONTACT_LINK) 
    return render_template_string(HTML, authed=True, logo=LOGO_URL, total_users=get_total_active_users(), msg=session.pop("msg", None), err=session.pop("err", None), IP=SERVER_IP_FALLBACK)

@app.route("/users", methods=["GET"])
def users_table_view():
    if require_login(): return redirect(url_for('login'))
    view, today_str, today_date = prepare_user_data() 
    return render_template("users_table_wrapper.html", users=view, today_date=today_date, err=session.pop("err", None)) 

@app.route("/login", methods=["GET","POST"])
def login():
  if request.method=="POST":
    if hmac.compare_digest((request.form.get("u") or "").strip(), ADMIN_USER) and hmac.compare_digest((request.form.get("p") or "").strip(), ADMIN_PASS):
      session["auth"]=True; return redirect(url_for('index'))
    session["login_err"]="❌ Username သို့မဟုတ် Password မှားနေပါသည်"
  return redirect(url_for('index'))

@app.route("/add", methods=["POST"])
def add_user():
  if require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip(); password=(request.form.get("password") or "").strip(); expires=(request.form.get("expires") or "").strip()
  ip = (request.form.get("ip") or "").strip() or SERVER_IP_FALLBACK # 💡 Get IP
  
  if re.compile(r'[\u1000-\u109F]').search(user) or re.compile(r'[\u1000-\u109F]').search(password):
      session["err"] = "❌ မြန်မာစာလုံးများ ခွင့်မပြုပါ"; return redirect(url_for('index'))
  if expires.isdigit(): expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower(): u["password"]=password; u["expires"]=expires; replaced=True; break
  if not replaced: users.append({"user":user,"password":password,"expires":expires})
  
  save_users(users); sync_config_passwords()
  
  # 💡 Added back the JSON message for the Copy Card popup
  msg_dict = { "user": user, "password": password, "expires": expires, "ip": ip }
  session["msg"] = json.dumps(msg_dict)
  
  return redirect(url_for('index'))

@app.route("/edit", methods=["POST"])
def edit_user():
  if require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip(); new_password=(request.form.get("password") or "").strip(); new_expires=(request.form.get("expires") or "").strip()
  if new_expires.isdigit(): new_expires=(datetime.now() + timedelta(days=int(new_expires))).strftime("%Y-%m-%d")
  users=load_users()
  for u in users:
    if u.get("user","").lower()==user.lower(): u["password"]=new_password; u["expires"]=new_expires; break
  save_users(users); sync_config_passwords()
  return redirect(url_for('users_table_view'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if require_login(): return redirect(url_for('login'))
  delete_user((request.form.get("user") or "").strip()); return redirect(url_for('users_table_view'))

@app.route("/logout", methods=["GET"])
def logout(): session.clear(); return redirect(url_for('index'))

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=-/etc/zivpn/web.env
WorkingDirectory=/etc/zivpn 
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

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
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table_wrapper.html || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZAWVPN PRO (Cyberpunk Version) အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။${Z}"
echo -e "${C}Web Panel (Admin)  :${Z} ${Y}http://$IP:8080${Z}"
echo -e "$LINE"
