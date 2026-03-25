#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX + Expiry Logic Update + Status FIX + PASSWORD & EXPIRY EDIT FEATURE + LOGOUT FIX
set -euo pipefail

# ===== Pretty (CLEANED UP) =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (Password နှင့် သက်တမ်းကုန်ဆုံးချိန်ပါ ပြင်လို့ရအောင် အဆင့်မြှင့်ထားပါသည်)${Z}"
    echo -e "$LINE"
    echo -e "${C}သက်တမ်းကုန်ဆုံးသည့်နေ့ ည ၁၁:၅၉:၅၉ အထိ သုံးခွင့်ပေးပြီးမှ ဖျက်ပါမည်။${Z}\n"
}
say 

# ===== Root check (unchanged) =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards (unchanged for brevity) =====
wait_for_apt() {
  echo -e "${Y}⏳ apt သင့်လျော်မှုကို စောင့်ပါ...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  echo -e "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
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

# ===== Packages (unchanged) =====
echo -e "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths and setup directories (unchanged) =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
TEMPLATES_DIR="/etc/zivpn/templates" 
mkdir -p /etc/zivpn "$TEMPLATES_DIR" 

# --- ZIVPN Binary, Config, Certs (UNCHANGED) ---
echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

if [ ! -f "$CFG" ]; then
  echo -e "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  echo -e "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=M-69P/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# --- Web Admin Login, VPN Passwords, config.json Update, systemd: ZIVPN (MODIFIED) ---
echo -e "${G}🔒 Web Admin Login UI ထည့်မလား..?${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  
  echo -e "${G}🔗 Login အောက်နားတွင် ပြသရန် ဆက်သွယ်ရန် Link (Optional)${Z}"
  read -r -p "Contact Link (ဥပမာ: https://m.me/taknds69 or Enter=disable): " CONTACT_LINK
  
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
  echo -e "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  echo -e "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: M-69P,tak,dtac69${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
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

echo -e "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
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

# 💡 Mobile Friendly: users_table.html
echo -e "${Y}📄 Table HTML (users_table.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table.html" <<'TABLE_HTML'
<div class="table-container">
    <table>
      <thead>
          <tr>
            <th><i class="icon">👤</i> User</th>
            <th><i class="icon">🔑</i> Password</th>
            <th><i class="icon">⏰</i> Expires</th>
            <th><i class="icon">🚦</i> Status</th> 
            <th><i class="icon">❌</i> Action</th>
          </tr>
      </thead>
      <tbody>
          {% for u in users %}
          <tr class="{% if u.expires and u.expires_date < today_date %}expired{% elif u.expiring_soon %}expiring-soon{% endif %}">
            <td data-label="User">{% if u.expires and u.expires_date < today_date %}<s>{{u.user}}</s>{% else %}{{u.user}}{% endif %}</td>
            <td data-label="Password">{% if u.expires and u.expires_date < today_date %}<s>{{u.password}}</s>{% else %}{{u.password}}{% endif %}</td>
            <td data-label="Expires">
                {% if u.expires %}
                    {% if u.expires_date < today_date %}
                        <s>{{u.expires}} (Expired)</s>
                    {% else %}
                        {% if u.expiring_soon %}
                            <span class="text-expiring">{{u.expires}}</span>
                        {% else %}
                            {{u.expires}}
                        {% endif %}
                        
                        <br><span class="days-remaining">
                            (ကျန်ရှိ: 
                            {% if u.days_remaining is not none %}
                                {% if u.days_remaining == 0 %}
                                    <span class="text-expiring">ဒီနေ့ နောက်ဆုံး</span>
                                {% else %}
                                    {{ u.days_remaining }} ရက်
                                {% endif %}
                            {% else %}
                                —
                            {% endif %}
                            )
                        </span>
                    {% endif %}
                {% else %}
                    <span class="muted">—</span>
                {% endif %}
            </td>
            
            <td data-label="Status">
                {% if u.expires and u.expires_date < today_date %}
                    <span class="pill pill-expired"><i class="icon">🛑</i> Expired</span>
                {% elif u.expiring_soon %}
                    <span class="pill pill-expiring"><i class="icon">⚠️</i> Expiring Soon</span>
                {% else %}
                    <span class="pill ok"><i class="icon">🟢</i> Active</span>
                {% endif %}
            </td>

            <td data-label="Action">
              <button type="button" class="btn-edit" onclick="showEditModal('{{ u.user }}', '{{ u.password }}', '{{ u.expires }}')"><i class="icon">✏️</i> Edit</button>
              <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်မလား?')">
                <input type="hidden" name="user" value="{{u.user}}">
                <button type="submit" class="btn-delete"><i class="icon">🗑️</i> Delete</button>
              </form>
            </td>
          </tr>
          {% endfor %}
      </tbody>
    </table>
</div>

<div id="editModal" class="modal">
  <div class="modal-content">
    <span class="close-btn" onclick="document.getElementById('editModal').style.display='none'">&times;</span>
    <h2 class="section-title"><i class="icon">✏️</i> Edit Account</h2>
    <form method="post" action="/edit">
        <input type="hidden" id="edit-user" name="user">
        
        <div class="input-group">
            <label for="current-user-display" class="input-label"><i class="icon">👤</i> User Name</label>
            <div class="input-field-wrapper is-readonly">
                <input type="text" id="current-user-display" name="current_user_display" readonly>
            </div>
        </div>
        
        <div class="input-group">
            <label for="new-password" class="input-label"><i class="icon">🔒</i> Password</label>
            <div class="input-field-wrapper">
                <input type="text" id="new-password" name="password" required>
            </div>
            <p class="input-hint">Password အသစ် (မပြောင်းလဲလိုပါက ဒီအတိုင်းထားပါ)</p>
        </div>

        <div class="input-group">
            <label for="new-expires" class="input-label"><i class="icon">🗓️</i> Expiry Date</label>
            <div class="input-field-wrapper">
                <input type="text" id="new-expires" name="expires" placeholder="ဥပမာ: 30 သို့မဟုတ် 2026-12-31" required>
            </div>
            <p class="input-hint">ကုန်ဆုံးမည့် ရက်စွဲအသစ် သို့မဟုတ် ရက်အရေအတွက် ထည့်ပါ</p>
        </div>
        
        <button class="save-btn modal-save-btn" type="submit">ပြင်ဆင်ချက်များ သိမ်းမည်</button>
    </form>
  </div>
</div>

<style>
/* MODAL UI UPDATE START (NEON THEME) */
.modal-content {
  background-color: var(--card-bg); 
  margin: 15% auto; 
  padding: 25px; 
  border: 1px solid var(--border-color); 
  width: 90%; 
  max-width: 320px; 
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 40px rgba(0, 229, 255, 0.15); 
}
.close-btn { 
  color: var(--secondary); 
  position: absolute; 
  top: 8px; 
  right: 15px; 
  font-size: 32px; 
  font-weight: 300; 
  transition: color 0.2s;
  line-height: 1; 
  cursor: pointer;
}
.close-btn:hover { color: var(--danger); }
.section-title { margin-top: 0; padding-bottom: 10px; border-bottom: 1px solid var(--border-color); color: var(--primary); text-shadow: 0 0 10px rgba(0, 229, 255, 0.3);}

.modal .input-group { margin-bottom: 20px; }
.modal .input-label { display: block; text-align: left; font-weight: 600; color: #fff; font-size: 0.9em; margin-bottom: 5px; }
.modal .input-field-wrapper { display: flex; align-items: center; border: 1px solid var(--border-color); border-radius: 8px; background-color: var(--bg-color); transition: all 0.3s; }
.modal .input-field-wrapper:focus-within { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(0, 229, 255, 0.2); }
.modal .input-field-wrapper.is-readonly { background-color: var(--light); opacity: 0.8; }
.modal .input-field-wrapper input { width: 100%; padding: 12px 10px; border: none; border-radius: 8px; font-size: 16px; outline: none; background: transparent; color: #fff; }
.modal .input-hint { margin-top: 5px; text-align: left; font-size: 0.75em; color: var(--secondary); line-height: 1.4; padding-left: 5px; }

.modal-save-btn { width: 100%; padding: 12px; background-color: var(--primary); color: #0b0f19; border: none; border-radius: 8px; font-size: 1.0em; cursor: pointer; transition: all 0.3s; margin-top: 10px; font-weight: bold; box-shadow: 0 0 10px rgba(0, 229, 255, 0.4);}
.modal-save-btn:hover { background-color: var(--primary-dark); color: #fff; box-shadow: 0 0 15px rgba(0, 229, 255, 0.6);} 
.modal-save-btn:active { transform: translateY(1px); }

.btn-edit { background-color: rgba(0, 229, 255, 0.1); color: var(--primary); border: 1px solid rgba(0, 229, 255, 0.3); padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: all 0.2s; margin-right: 5px; }
.btn-edit:hover { background-color: var(--primary); color: #0b0f19; box-shadow: 0 0 10px rgba(0, 229, 255, 0.4);}
.delform { display: inline-block; margin: 0; }
.btn-delete { padding: 6px 10px; font-size: 0.9em; } 

.days-remaining { font-size: 0.85em; color: var(--secondary); font-weight: 500; display: inline-block; margin-top: 2px; }
.days-remaining .text-expiring { font-weight: bold; }

@media (max-width: 768px) {
    td[data-label="Action"] { display: flex; justify-content: flex-end; align-items: center; }
    .btn-edit { width: 80px; padding: 6px 8px; font-size: 0.8em; }
    .btn-delete { width: 80px; padding: 6px 8px; font-size: 0.8em; margin-top: 0; }
    .modal-content { margin: 20% auto; max-width: 280px; }
    .days-remaining { display: block; text-align: right; }
}
/* MODAL UI UPDATE END */
</style>

<script>
    function showEditModal(user, password, expires) {
        document.getElementById('edit-user').value = user;
        document.getElementById('current-user-display').value = user;
        
        // Pre-fill fields with current values so user only modifies what they want
        document.getElementById('new-password').value = password;
        document.getElementById('new-expires').value = expires;
        
        document.getElementById('editModal').style.display = 'block';
    }

    window.onclick = function(event) {
        if (event.target == document.getElementById('editModal')) {
            document.getElementById('editModal').style.display = 'none';
        }
    }
</script>
TABLE_HTML

# 💡 Mobile Friendly: users_table_wrapper.html 
echo -e "${Y}📄 Table Wrapper (users_table_wrapper.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table_wrapper.html" <<'WRAPPER_HTML'
<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel - Users</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles for Mobile UI (NEON/CYBERPUNK THEME) */
:root {
    --primary: #00e5ff; 
    --primary-dark: #00b8d4; 
    --secondary: #90a4ae; 
    --success: #00e676; 
    --danger: #ff1744;
    --light: #263238; 
    --dark: #eceff1; 
    --bg-color: #0b0f19; 
    --card-bg: #111827;
    --border-color: #1f2937;
    --warning: #ffea00;
    --warning-bg: rgba(255, 234, 0, 0.15);
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px;
}
.icon { font-style: normal; margin-right: 5px; }

.main-header { display: flex; justify-content: space-between; align-items: center; background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 2px 15px rgba(0, 229, 255, 0.1); border-bottom: 1px solid var(--border-color); margin-bottom: 15px; position: sticky; top: 0; z-index: 1000; }
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none; text-shadow: 0 0 8px rgba(0, 229, 255, 0.4);}
.header-logo .highlight { color: #fff; text-shadow: none;}

.bottom-nav { display: flex; justify-content: space-around; align-items: center; position: fixed; bottom: 0; left: 0; width: 100%; background-color: rgba(17, 24, 39, 0.95); backdrop-filter: blur(10px); box-shadow: 0 -2px 20px rgba(0, 229, 255, 0.15); border-top: 1px solid var(--border-color); z-index: 1000; padding: 5px 0; }
.bottom-nav a { display: flex; flex-direction: column; align-items: center; text-decoration: none; color: var(--secondary); font-size: 0.75em; padding: 8px; border-radius: 6px; transition: color 0.3s, text-shadow 0.3s; min-width: 80px; }
.bottom-nav a:hover, .bottom-nav a.active { color: var(--primary); text-shadow: 0 0 5px rgba(0, 229, 255, 0.5);}
.bottom-nav a i.icon { font-size: 1.2em; margin-right: 0; margin-bottom: 3px; color: #81d4fa; filter: drop-shadow(0 0 2px rgba(129, 212, 250, 0.5));}
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon { color: var(--primary); filter: drop-shadow(0 0 8px rgba(0, 229, 255, 0.8));}

.table-container { padding: 0 10px; margin: 0 auto; max-width: 100%; } 
table { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px; background-color: var(--card-bg); box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4); border-radius: 8px; overflow: hidden; border: 1px solid var(--border-color);}
th, td { padding: 10px; text-align: left; border-bottom: 1px solid var(--border-color); font-size: 0.9em; color: var(--dark);}
th { background-color: #1a2235; color: var(--primary); font-weight: 600; text-transform: uppercase; font-size: 0.8em; letter-spacing: 0.5px;} 
tr:last-child td { border-bottom: none; }
tr:nth-child(even) { background-color: #141c2b; }
tr:hover { background-color: #1e293b; }

@media (max-width: 768px) {
    .table-container { padding: 0 5px; }
    table, thead, tbody, th, td, tr { display: block; border: none;}
    table { background-color: transparent; box-shadow: none;}
    thead { display: none; } 
    tr { background-color: var(--card-bg) !important; border: 1px solid var(--border-color); margin-bottom: 15px; border-radius: 8px; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.3); }
    td { border: none; position: relative; padding-left: 45%; text-align: right; border-bottom: 1px dashed var(--border-color); }
    td:last-child { border-bottom: none; }
    td:before { content: attr(data-label); position: absolute; left: 0; width: 40%; padding-left: 10px; font-weight: bold; text-align: left; color: var(--primary); font-size: 0.9em; }
    .pill { padding: 4px 8px; font-size: 0.8em; min-width: 70px; }
    .delform { display: block; text-align: right; }
    .btn-delete { width: 80px; padding: 6px 8px; font-size: 0.8em; margin-top: 5px;}
    .days-remaining { display: block !important; }
}

.main-nav { display: none; } 
@media (min-width: 769px) { .bottom-nav { display: none; } body { padding-bottom: 0; } }

.pill { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 15px; font-size: 0.85em; font-weight: bold; min-width: 90px; justify-content: center;}
.ok { background-color: rgba(0, 230, 118, 0.15); color: var(--success); border: 1px solid rgba(0, 230, 118, 0.3); box-shadow: 0 0 8px rgba(0, 230, 118, 0.2);} 
.pill-expired { background-color: rgba(255, 23, 68, 0.15); color: var(--danger); border: 1px solid rgba(255, 23, 68, 0.3); box-shadow: 0 0 8px rgba(255, 23, 68, 0.2);}
.pill-expiring { background-color: var(--warning-bg); color: var(--warning); border: 1px solid rgba(255, 234, 0, 0.3); box-shadow: 0 0 8px rgba(255, 234, 0, 0.2);} 
.text-expiring { color: var(--warning); font-weight: bold; } 
.days-remaining { font-size: 0.85em; color: var(--secondary); font-weight: 500; display: inline-block; margin-top: 2px; }
.days-remaining .text-expiring { font-weight: bold; }
tr.expired td { opacity: 0.5; text-decoration-color: var(--danger); }
tr.expiring-soon { border-left: 4px solid var(--warning); } 

.btn-delete { background-color: rgba(255, 23, 68, 0.1); color: var(--danger); border: 1px solid rgba(255, 23, 68, 0.3); padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: all 0.2s;}
.btn-delete:hover { background-color: var(--danger); color: #fff; box-shadow: 0 0 10px rgba(255, 23, 68, 0.4);}

.modal { display: none; position: fixed; z-index: 3000; left: 0; top: 0; width: 100%; height: 100%; overflow: auto; background-color: rgba(11, 15, 25, 0.8); backdrop-filter: blur(4px);}
/* Model CSS imported via users_table.html */
</style>
</head><body>
    
    <header class="main-header">
        <div class="header-logo">
            <a href="/">ZIVPN<span class="highlight"> Panel</span></a>
        </div>
    </header>
    
{% if err %}
<div class="boxa1">
    <div class="err" style="text-align: center;">{{ err }}</div>
</div>
{% endif %}

{% include 'users_table.html' %}

    <nav class="bottom-nav">
        <a href="/">
            <i class="icon">➕</i>
            <span>အကောင့်ထည့်ရန်</span>
        </a>
        <a href="/users" class="active">
            <i class="icon">📜</i>
            <span>အသုံးပြုသူ စာရင်း</span>
        </a>
        <a href="/logout">
            <i class="icon">➡️</i>
            <span>ထွက်ရန်</span>
        </a>
    </nav>

</body></html>
WRAPPER_HTML

# 💡 Web Panel (Flask - web.py)
echo -e "${Y}🖥️ Web Panel (web.py) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta, date

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://zivpn-web.free.nf/zivpn-icon.png"

def get_server_ip():
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        ip = result.stdout.strip().split()[0]
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip):
            return ip
    except Exception:
        pass
    return "127.0.0.1" 

SERVER_IP_FALLBACK = get_server_ip()
CONTACT_LINK = os.environ.get("WEB_CONTACT_LINK", "").strip()

# HTML Template (NEON THEME UI WITH FIRE GLOW EFFECT)
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles */
:root { --primary: #00e5ff; --primary-dark: #00b8d4; --secondary: #90a4ae; --success: #00e676; --danger: #ff1744; --light: #263238; --dark: #eceff1; --bg-color: #0b0f19; --card-bg: #111827; --border-color: #1f2937; --warning: #ffea00; }
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color); line-height: 1.6; color: var(--dark); margin: 0; padding: 0; padding-bottom: 70px; }
.icon { font-style: normal; margin-right: 5px; }
.main-header { display: flex; justify-content: space-between; align-items: center; background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 2px 15px rgba(0, 229, 255, 0.1); border-bottom: 1px solid var(--border-color); margin-bottom: 15px; position: sticky; top: 0; z-index: 1000; }
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none; text-shadow: 0 0 8px rgba(0, 229, 255, 0.4);} 
.header-logo .highlight { color: #fff; text-shadow: none;}
.bottom-nav { display: flex; justify-content: space-around; align-items: center; position: fixed; bottom: 0; left: 0; width: 100%; background-color: rgba(17, 24, 39, 0.95); backdrop-filter: blur(10px); box-shadow: 0 -2px 20px rgba(0, 229, 255, 0.15); border-top: 1px solid var(--border-color); z-index: 1000; padding: 5px 0; }
.bottom-nav a { display: flex; flex-direction: column; align-items: center; text-decoration: none; color: var(--secondary); font-size: 0.75em; padding: 8px; border-radius: 6px; transition: color 0.3s, text-shadow 0.3s; min-width: 80px; }
.bottom-nav a:hover, .bottom-nav a.active { color: var(--primary); text-shadow: 0 0 5px rgba(0, 229, 255, 0.5);}
.bottom-nav a i.icon { font-size: 1.2em; margin-right: 0; margin-bottom: 3px; color: #81d4fa; filter: drop-shadow(0 0 2px rgba(129, 212, 250, 0.5));}
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon { color: var(--primary); filter: drop-shadow(0 0 8px rgba(0, 229, 255, 0.8));}
@media (min-width: 769px) { .bottom-nav { display: none; } body { padding-bottom: 0; } }
.login-container, .boxa1 { background-color: var(--card-bg); padding: 30px 20px; border-radius: 12px; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6); border: 1px solid var(--border-color); width: 90%; max-width: 400px; margin: 30px auto; text-align: center; }
.boxa1 { max-width: 600px; margin-top: 15px; text-align: left; }
.info-card { background-color: rgba(0, 229, 255, 0.05); color: var(--primary); padding: 15px 20px; border-radius: 8px; text-align: center; font-weight: bold; font-size: 1.0em; margin-bottom: 15px; border: 1px solid rgba(0, 229, 255, 0.2); box-shadow: inset 0 0 15px rgba(0, 229, 255, 0.1); }
.info-card span { font-size: 1.1em; margin-right: 5px; color: #fff; text-shadow: 0 0 5px rgba(255,255,255,0.5);}

/* 💡 FIRE GLOW ANIMATION START */
@keyframes fireGlow {
    0% { box-shadow: 0 0 10px #ff2a00, 0 0 20px #ff7a00, 0 0 30px #ffce00, 0 0 40px rgba(255, 206, 0, 0.5); border-color: #ff2a00; }
    50% { box-shadow: 0 0 15px #ff2a00, 0 0 30px #ff7a00, 0 0 45px #ffce00, 0 0 60px rgba(255, 206, 0, 0.8); border-color: #ffce00; }
    100% { box-shadow: 0 0 10px #ff2a00, 0 0 20px #ff7a00, 0 0 30px #ffce00, 0 0 40px rgba(255, 206, 0, 0.5); border-color: #ff2a00; }
}
.profile-image-container { 
    display: inline-block; 
    margin-bottom: 25px; 
    border-radius: 50%; 
    overflow: hidden; 
    border: 3px solid #ff7a00; 
    animation: fireGlow 1s infinite alternate;
    background-color: #000;
}
.profile-image { width: 80px; height: 80px; object-fit: cover; display: block; }
/* 💡 FIRE GLOW ANIMATION END */

h1 { font-size: 24px; color: #fff; margin-bottom: 5px; text-shadow: 0 0 10px rgba(0, 229, 255, 0.3);}
.panel-title { font-size: 14px; color: var(--secondary); margin-bottom: 25px; }
.login-ip-display { font-size: 16px; color: var(--primary); font-weight: bold; margin-top: -15px; margin-bottom: 25px; letter-spacing: 1px;}
.input-group { margin-bottom: 15px; text-align: left; }
.input-field-wrapper { display: flex; align-items: center; border: 1px solid var(--border-color); border-radius: 8px; margin-Top: 5px; background-color: var(--bg-color); transition: all 0.3s; }
.input-field-wrapper:focus-within { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(0, 229, 255, 0.2); }
.input-field-wrapper .icon { padding: 0 10px; color: var(--secondary); background: transparent; }
input[type="text"], input[type="password"], input[name="expires"], input[name="port"], input[name="ip"] { width: 100%; padding: 12px 10px; border: none; border-radius: 0 8px 8px 0; font-size: 16px; outline: none; background: transparent; color: #fff; appearance: none; -webkit-appearance: none; }
input[name="ip"] { background-color: #1a2235; color: var(--primary); cursor: pointer; font-weight: bold;}
.login-button, .save-btn { width: 100%; padding: 12px; background-color: var(--primary); color: #0b0f19; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; transition: all 0.3s; margin-top: 20px; font-weight: bold; box-shadow: 0 0 10px rgba(0, 229, 255, 0.4);}
.login-button:hover, .save-btn:hover { background-color: var(--primary-dark); color: #fff; box-shadow: 0 0 20px rgba(0, 229, 255, 0.6);} 
.login-button:active, .save-btn:active { transform: translateY(1px); } 
.section-title { font-size: 18px; font-weight: bold; color: var(--primary); margin-bottom: 15px; }
.row{display:flex;gap:15px;flex-wrap:wrap;margin-bottom: 5px;}
.row>div{flex:1 1 100%;}
@media (min-width: 600px) { .row>div{flex:1 1 220px;} }
.err{ color: var(--danger); background-color: rgba(255, 23, 68, 0.1); border: 1px solid rgba(255, 23, 68, 0.3); padding: 10px; border-radius: 8px; margin-bottom: 15px; font-weight: bold; text-align: center; box-shadow: 0 0 10px rgba(255, 23, 68, 0.2);}
.user-info-card { position: fixed; top: 20px; left: 50%; transform: translateX(-50%); background-color: rgba(0, 230, 118, 0.15); color: var(--success); border: 1px solid rgba(0, 230, 118, 0.4); border-radius: 8px; padding: 15px 20px; box-shadow: 0 10px 30px rgba(0, 230, 118, 0.2); z-index: 2000; max-width: 300px; width: 90%; text-align: left; backdrop-filter: blur(8px);}
#copy-notification { position: fixed; top: 10px; right: 50%; transform: translateX(50%); background-color: var(--success); color: #0b0f19; font-weight: bold; padding: 8px 15px; border-radius: 5px; z-index: 2000; font-size: 0.9em; opacity: 0; transition: opacity 0.5s; box-shadow: 0 4px 15px rgba(0, 230, 118, 0.4);}
text { font-size: 15px; margin-Top: 0px; color: var(--secondary);}
.contact-link { margin-top: 15px; font-size: 0.9em; font-weight: 500; }
.contact-link a { color: var(--primary); text-decoration: none; font-weight: bold; transition: all 0.3s; }
.contact-link a:hover { color: #fff; text-shadow: 0 0 8px rgba(0, 229, 255, 0.6); }
</style>
<script>
    function copyToClipboard(elementId) {
        const copyText = document.getElementById(elementId);
        if (!copyText) return;
        const notification = document.getElementById('copy-notification');
        const showNotification = () => {
            notification.innerText = 'Server IP ကို ကူးပြီးပါပြီ';
            notification.style.opacity = 1;
            setTimeout(() => { notification.style.opacity = 0; }, 2000);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(copyText.value).then(showNotification).catch(err => { fallbackCopy(copyText, showNotification); });
        } else {
            fallbackCopy(copyText, showNotification);
        }
    }
    function fallbackCopy(copyText, onSuccess) {
        let isCopied = false;
        try {
            copyText.select();
            copyText.setSelectionRange(0, 99999); 
            isCopied = document.execCommand('copy');
            if (isCopied) { onSuccess(); } else { console.error('Copy failed using execCommand'); }
        } catch (err) { console.error('Fallback copy failed: ', err); }
    }
</script>
</head><body>
{% if not authed %}
    <div class="login-container">
        <div class="profile-image-container"><img src="{{logo}}" alt="Profile" class="profile-image"></div>
        <h1>ZIVPN Panel</h1>
        <br>
        {% if IP %}<p class="login-ip-display">Server IP: {{ IP }}</p>{% endif %}
        <p class="panel-title">Login to Admin Dashboard</p>
        {% if err %}<div class="err">{{err}}</div>{% endif %} <form action="/login" method="POST" class="login-form">
            <div class="input-group">
                <label for="username" style="display:none;">Username</label>
                <div class="input-field-wrapper"><i class="icon">🔑</i><input type="text" id="username" name="u" placeholder="Username" required></div>
            </div>
            <div class="input-group">
                <label for="password" style="display:none;">Password</label>
                <div class="input-field-wrapper"><i class="icon">🔒</i><input type="password" id="password" name="p" placeholder="Password" required></div>
            </div>
            <button type="submit" class="login-button">Login</button>
        </form>
        {% if contact_link %}
        <p class="contact-link"><i class="icon">🗨️</i><a href="{{ contact_link }}" target="_blank">Admin ကို ဆက်သွယ်ပါ</a></p>
        {% endif %}
    </div>
{% else %}
   <header class="main-header">
        <div class="header-logo"><a href="/">ZIVPN<span class="highlight"> Panel</span></a></div>
    </header>
    <div id="copy-notification"></div> <div class="boxa1">
        <div class="info-card">
            <i class="icon">💡</i> လက်ရှိ Member User စုစုပေါင်း<br><span>{{ total_users }}</span>ယောက်
        </div>
    <script>
        {% if msg and '{' in msg and '}' in msg %}
        try {
            const data = JSON.parse('{{ msg | safe }}');
            if (data.user) { 
                const card = document.createElement('div');
                card.className = 'user-info-card';
                if (data.message) {
                    card.innerHTML = data.message;
                } else {
                    card.innerHTML = `
                        <h4 style="color:#fff; text-shadow:0 0 5px rgba(255,255,255,0.3);">✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ</h4>
                        <p><i class="icon">🔥</i> Server IP: <b style="color:var(--primary);">${data.ip || '{{ IP }}'}</b></p>  
                        <p><i class="icon">👤</i> Username: <b style="color:#fff;">${data.user}</b></p>
                        <p><i class="icon">🔑</i> Password: <b style="color:#fff;">${data.password}</b></p>
                        <p><i class="icon">⏰</i> Expires: <b style="color:#fff;">${data.expires || 'N/A'}</b></p>                   
                    `;
                }
                document.body.appendChild(card);
                setTimeout(() => { if (card.parentNode) { card.parentNode.removeChild(card); } }, 20000); 
            }
        } catch (e) { console.error("Error parsing message JSON:", e); }
        {% endif %}
    </script>
    <form method="post" action="/add" class="">
        <h2 class="section-title"><i class="icon">➕</i> Add new user</h2>
        {% if err %}<div class="err">{{err}}</div>{% endif %}
        <div class="input-group">
            <label for="username" style="display:none;">Username</label>
            <div class="input-field-wrapper"><i class="icon">👤</i><input type="text" id="username" name="user" placeholder="Username" required></div>
        </div>
        <div class="input-group">
            <label for="password" style="display:none;">Password</label>
            <div class="input-field-wrapper"><i class="icon">🔑</i><input type="password" id="password" name="password" placeholder="Password" required></div>
        </div>
        <div class="row">
            <div>
            <text> <label><i class="icon"></i>Add (expiration date)</label></text>
            <tak1>  <div class="input-field-wrapper">
                <i class="icon">🗓️</i>
                <input name="expires" required placeholder="Example : 2025-12-31 or 30">
            </div></tak1>
            </div>
        </div>
        <div class="input-group">
            <label><i class="icon"></i>Server IP (Click to Copy)</label> 
            <div class="input-field-wrapper"><i class="icon">📡</i><input name="ip" id="server-ip-input" placeholder="ip" value="{{ IP }}" readonly onclick="copyToClipboard('server-ip-input')"></div>
        </div>
        <button class="save-btn" type="submit">Create Account</button>
    </form>
    </div> <nav class="bottom-nav">
        <a href="/" class="active"><i class="icon">➕</i><span>အကောင့်ထည့်ရန်</span></a>
        <a href="/users"><i class="icon">📜</i><span>အသုံးပြုသူ စာရင်း</span></a>
        <a href="/logout"><i class="icon">➡️</i><span>ထွက်ရန်</span></a>
    </nav>
{% endif %}
</body></html>"""

app = Flask(__name__, template_folder="/etc/zivpn/templates")
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","M-69P").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","M-69P").strip()

def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception: return default
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
  for u in v:
    out.append({"user":u.get("user",""), "password":u.get("password",""), "expires":u.get("expires",""), "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out
def save_users(users): write_json_atomic(USERS_FILE, users)

def get_total_active_users():
    users = load_users()
    today_date = date.today() 
    active_count = 0
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                is_expired = False
        if not is_expired:
            active_count += 1
    return active_count

def is_expiring_soon(expires_str):
    if not expires_str: return False
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today() 
        remaining_days = (expires_date - today).days
        return 0 <= remaining_days <= 1
    except ValueError:
        return False
    
def calculate_days_remaining(expires_str):
    if not expires_str: return None
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        remaining = (expires_date - today).days
        return remaining if remaining >= 0 else None
    except ValueError:
        return None
    
def delete_user(user):
    users = load_users()
    remaining_users = [u for u in users if u.get("user").lower() != user.lower()]
    save_users(remaining_users)
    sync_config_passwords(mode="mirror")
    
def check_user_expiration():
    users = load_users()
    today_date = date.today() 
    users_to_keep = []
    deleted_count = 0
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                pass 
        if is_expired:
            deleted_count += 1
        else:
            users_to_keep.append(user)
    if deleted_count > 0:
        save_users(users_to_keep)
        sync_config_passwords(mode="mirror") 
        return True 
    return False 

def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  today_date = date.today() 
  valid_passwords = set()
  for u in users:
      expires_str = u.get("expires")
      is_valid = True
      if expires_str:
          try:
              if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                  is_valid = False
          except ValueError:
              is_valid = True 
      if is_valid and u.get("password"):
          valid_passwords.add(str(u["password"]))
  users_pw=sorted(list(valid_passwords))
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
    
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  cfg["listen"]=cfg.get("listen") or ":5667"
  cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
  cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
  cfg["obfs"]=cfg.get("obfs") or "zivpn"
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login(): return False if login_enabled() and not is_authed() else True

def prepare_user_data():
    all_users = load_users()
    check_user_expiration() 
    users = load_users()
    view=[]
    today_date = date.today()
    for u in users:
      expires_date_obj = None
      if u.get("expires"):
          try: expires_date_obj = datetime.strptime(u.get("expires"), "%Y-%m-%d").date()
          except ValueError: pass
      view.append(type("U",(),{
        "user":u.get("user",""), "password":u.get("password",""), "expires":u.get("expires",""),
        "expires_date": expires_date_obj, "days_remaining": calculate_days_remaining(u.get("expires","")),
        "port":u.get("port",""), "expiring_soon": is_expiring_soon(u.get("expires","")) 
      }))
    view.sort(key=lambda x:(x.user or "").lower())
    today=datetime.now().strftime("%Y-%m-%d")
    return view, today, today_date

@app.route("/", methods=["GET"])
def index(): 
    server_ip = SERVER_IP_FALLBACK 
    if not require_login():
      return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), IP=server_ip, contact_link=CONTACT_LINK) 
    check_user_expiration()
    total_users = get_total_active_users()
    return render_template_string(HTML, authed=True, logo=LOGO_URL, total_users=total_users, msg=session.pop("msg", None), err=session.pop("err", None), today=datetime.now().strftime("%Y-%m-%d"), IP=server_ip)

@app.route("/users", methods=["GET"])
def users_table_view():
    if not require_login(): return redirect(url_for('login'))
    view, today_str, today_date = prepare_user_data() 
    return render_template("users_table_wrapper.html", users=view, today=today_str, today_date=today_date, logo=LOGO_URL, IP=SERVER_IP_FALLBACK, msg=session.pop("msg", None), err=session.pop("err", None)) 

@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled(): return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True; return redirect(url_for('index'))
    else:
      session["auth"]=False; session["login_err"]="❌ Username သို့မဟုတ် Password မှားယွင်းနေပါသည်။ ထပ်မံစစ်ဆေးပါ။" ; return redirect(url_for('login'))
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), IP=SERVER_IP_FALLBACK, contact_link=CONTACT_LINK)

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip() 
  ip = (request.form.get("ip") or "").strip() or SERVER_IP_FALLBACK

  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(user) or myanmar_chars_pattern.search(password):
      session["err"] = "❌ User Name သို့မဟုတ် Password တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။ (English, Numbers သာ ခွင့်ပြုသည်)"
      return redirect(url_for('index'))

  if expires.isdigit(): expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    session["err"] = "User Name နှင့် Password များ မပါဝင်ပါ"; return redirect(url_for('index')) 
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      session["err"] = "Expires ရက်စွဲ မမှန်ပါ"; return redirect(url_for('index'))
  
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced: users.append({"user":user,"password":password,"expires":expires,"port":port})
  
  save_users(users)
  sync_config_passwords()

  msg_dict = { "user": user, "password": password, "expires": expires, "ip": ip }
  session["msg"] = json.dumps(msg_dict)
  return redirect(url_for('index'))

# 💡 ROUTE MODIFIED: Password နှင့် Expiry ပါ Edit လုပ်နိုင်ရန်
@app.route("/edit", methods=["POST"])
def edit_user_password():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  new_password=(request.form.get("password") or "").strip()
  new_expires=(request.form.get("expires") or "").strip()
  
  if not user or not new_password or not new_expires:
    session["err"] = "အချက်အလက်များ အပြည့်အစုံ မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
    
  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(new_password):
      session["err"] = "❌ Password အသစ်တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။"
      return redirect(url_for('users_table_view')) 
      
  # Handle Expiry Date Logic like /add
  if new_expires.isdigit(): 
      new_expires=(datetime.now() + timedelta(days=int(new_expires))).strftime("%Y-%m-%d")
  try: 
      datetime.strptime(new_expires,"%Y-%m-%d")
  except ValueError:
      session["err"] = "❌ ရက်စွဲပုံစံ မှားယွင်းနေပါသည်။"
      return redirect(url_for('users_table_view'))

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=new_password 
      u["expires"]=new_expires
      replaced=True
      break
      
  if not replaced:
    session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
    return redirect(url_for('users_table_view'))
    
  save_users(users)
  sync_config_passwords() 
  
  session["msg"] = json.dumps({"ok":True, "message": f"<h4 style='color:#fff;'>✅ **{user}** ရဲ့ အချက်အလက်များ ပြောင်းလဲပြီးပါပြီ။</h4><p>Password: <b style='color:#fff;'>{new_password}</b></p><p>Expiry: <b style='color:#fff;'>{new_expires}</b></p>", "user":user, "password":new_password})
  return redirect(url_for('users_table_view'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    session["err"] = "User Name မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
  delete_user(user) 
  return redirect(url_for('users_table_view'))

# 💡 LOGOUT ROUTE ADDED HERE (This fixes the white screen bug and prevents unauthorized access)
@app.route("/logout", methods=["GET"])
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd (unchanged) =====
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

# ===== Networking: forwarding + DNAT + MASQ + UFW (unchanged) =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize =====
echo -e "${Y}🧹 CRLF ရှင်းနေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html /etc/zivpn/templates/users_table_wrapper.html || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel (Add Users) :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Web Panel (User List) :${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|systemctl restart zivpn  •  systemctl status|systemctl restart zivpn-web${Z}"
echo -e "$LINE"
