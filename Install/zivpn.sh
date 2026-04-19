#!/bin/bash
# ZAW ZIVPN UDP MANAGER (CLASSIC UI + CLEAN TABLES + NO BUGGY LIMITS)

trap ' ' INT
set +e

update_zivpn() {
   python3 -c "
import json, sys, os
from datetime import datetime
ufile = '/etc/zivpn/users.json'; cfile = '/etc/zivpn/config.json'
try:
    with open(ufile, 'r') as f: users = json.load(f)
except: users = []
try:
    with open(cfile, 'r') as f: cfg = json.load(f)
except: cfg = {}
valid = set()
for u in users:
    exp = u.get('expires'); is_valid = True
    if exp:
        try:
            if datetime.strptime(exp.strip(), '%Y-%m-%d').date() < datetime.now().date(): is_valid = False
        except: pass
    if is_valid and u.get('password'): valid.add(str(u['password']))
if 'auth' not in cfg or not type(cfg['auth']) is dict: cfg['auth'] = {}
cfg['auth']['mode'] = 'passwords'
cfg['auth']['config'] = sorted(list(valid))
with open(cfile+'.tmp', 'w') as f: json.dump(cfg, f, indent=2)
os.rename(cfile+'.tmp', cfile)
" > /dev/null 2>&1
   systemctl restart zivpn.service > /dev/null 2>&1
}

IP=$(cat /etc/IP 2>/dev/null || wget -qO- ipv4.icanhazip.com 2>/dev/null)
if [[ -f /etc/domain ]]; then
    HOST_DOMAIN=$(cat /etc/domain | tr -d '\r' | tr -d '\n' | tr -d ' ')
    [[ -z "$HOST_DOMAIN" || "$HOST_DOMAIN" == "No-Domain" ]] && HOST_DOMAIN="$IP"
else
    HOST_DOMAIN="$IP"
fi

if [[ "$(grep -c "Ubuntu" /etc/issue.net)" = "1" ]]; then
    system=$(cut -d' ' -f1 /etc/issue.net); system+=$(echo ' '); system+=$(cut -d' ' -f2 /etc/issue.net |awk -F "." '{print $1}')
elif [[ "$(grep -c "Debian" /etc/issue.net)" = "1" ]]; then
    system=$(cut -d' ' -f1 /etc/issue.net); system+=$(echo ' '); system+=$(cut -d' ' -f3 /etc/issue.net)
else
    system=$(cut -d' ' -f1 /etc/issue.net)
fi

if [[ ! -f /etc/vps_country ]]; then
    _country=$(wget -qO- ip-api.com/line?fields=country 2>/dev/null); [[ -z "$_country" ]] && _country="Unknown"; echo "$_country" > /etc/vps_country
fi
_country=$(cat /etc/vps_country); _ip_pad=$(printf '%-15s' "$IP"); _ram=$(printf ' %-9s' "$(free -h | grep -i mem | awk '{print $2}')"); _usor=$(printf '%-8s' "$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')"); _usop=$(printf '%-1s' "$(top -bn1 | awk '/Cpu/ { cpu = "" 100 - $8 "%" }; END { print cpu }')"); _core=$(printf '%-1s' "$(grep -c ^processor /proc/cpuinfo)"); _system=$(printf '%-14s' "$system"); _hora=$(printf '%(%H:%M:%S)T')

show_account_table() {
    python3 -c "
import json
from datetime import datetime
try:
    with open('/etc/zivpn/users.json', 'r') as f: users = json.load(f)
except: users = []
print('\033[1;36m╔════╦══════════════╦════════════╦════════════╦═════════════╗\033[0m')
print('\033[1;36m║ \033[1;33mNO\033[1;36m ║ \033[1;33mUSERNAME\033[1;36m     ║ \033[1;33mPASSWORD\033[1;36m   ║ \033[1;33mEXPIRES\033[1;36m    ║ \033[1;33mSTATUS\033[1;36m      ║\033[0m')
print('\033[1;36m╠════╬══════════════╬════════════╬════════════╬═════════════╣\033[0m')
if not users:
    print('\033[1;31m║                 အကောင့်များ မရှိသေးပါ။ (No users found)                ║\033[0m')
else:
    today = datetime.now().date()
    for i, u in enumerate(users, 1):
        user = str(u.get('user', ''))[:12]; pwd = str(u.get('password', ''))[:10]; exp = str(u.get('expires', '')); status = '\033[1;32m✅ Active \033[0m'; color = '\033[1;37m'
        if exp:
            try:
                exp_date = datetime.strptime(exp.strip(), '%Y-%m-%d').date()
                if exp_date < today: status = '\033[1;31m❌ Expired\033[0m'; color = '\033[1;31m'
                elif exp_date == today: status = '\033[1;33m⚠️ Today  \033[0m'; color = '\033[1;33m'
            except: pass
        print('\033[1;36m║ \033[1;35m{:02d} \033[1;36m║ {}{:<12} \033[1;36m║ \033[1;37m{:<10} \033[1;36m║ {}{:<10} \033[1;36m║ {}\033[1;36m ║\033[0m'.format(i, color, user, pwd, color, exp, status))
print('\033[1;36m╚════╩══════════════╩════════════╩════════════╩═════════════╝\033[0m')
"
}

# နောက်ကွယ်က Limit cron job များရှိပါက ဖြုတ်ပစ်မည်
systemctl stop zlimit 2>/dev/null
systemctl disable zlimit 2>/dev/null
rm -f /usr/bin/zlimit /etc/systemd/system/zlimit.service

while true; do
stats=$(python3 -c "
import json
from datetime import datetime
try:
    with open('/etc/zivpn/users.json', 'r') as f: users = json.load(f)
    t = len(users); e = 0; tdy = 0; today = datetime.now().date()
    for u in users:
        exp = u.get('expires')
        if exp:
            try:
                exp_date = datetime.strptime(exp.strip(), '%Y-%m-%d').date()
                if exp_date < today: e += 1
                elif exp_date == today: tdy += 1
            except: pass
    print(f'{t-e} {e} {t} {tdy}')
except: print('0 0 0 0')
")
_onlin=$(printf '%-5s' "$(echo $stats | awk '{print $1}')"); _userexp=$(printf '%-5s' "$(echo $stats | awk '{print $2}')"); _tuser=$(echo $stats | awk '{print $3}'); _todayexp=$(echo $stats | awk '{print $4}')

clear
echo -e "           \033[38;5;226m███████████████████████████████\033[0m"
echo -e "           \033[38;5;40m██████████████\033[1;37m ★ \033[38;5;40m██████████████\033[0m"
echo -e "           \033[38;5;196m███████████████████████████████\033[0m"
echo -e "           \033[38;5;208m████████████\033[1;37m Z I V \033[38;5;208m████████████\033[0m\n"

_e_clean=$(echo $_userexp | tr -d ' ')
if [[ "$_todayexp" != "0" ]] || [[ "$_e_clean" != "0" ]]; then
    echo -e "    \033[1;33m⚠️ ယနေ့ကုန်မည်: $_todayexp ယောက် \033[1;37m| \033[1;31m🔴 သက်တမ်းလွန်: $_e_clean ယောက် \033[0m"
    echo ""
fi

echo -e "\033[1;36m╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮\033[0m"
echo -e "\033[1;36m┃\033[0;36m \033[1;35m✦ \E[44;1;37m ZIVPN UDP MANAGER Edit:@Zaw-ZivpnUdp-Script \E[0m\033[1;35m✦ \033[1;36m┃\033[0m"
echo -e "\033[1;36m┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\033[0m"
echo -e "\033[1;36m┃ \033[1;33mIP     :\033[1;37m $_ip_pad   \033[1;33mServer:\033[1;37m $_country\033[0m"
echo -e "\033[1;36m┃\033[0m"
echo -e "\033[1;36m┃ \033[1;33mDomain :\033[1;36m ✦ $HOST_DOMAIN ✦\033[0m"
echo -e "\033[1;36m┃\033[0m"
echo -e "\033[1;36m┃ \033[1;33mOS     :\033[1;37m $_system \033[1;33mRAM:\033[1;37m $_ram \033[1;33mCPU:\033[1;37m $_core\033[0m"
echo -e "\033[1;36m┃ \033[1;33mHora   :\033[1;37m $_hora     \033[1;33mUso:\033[1;37m $_usor \033[1;33mUso:\033[1;37m $_usop\033[0m"
echo -e "\033[1;36m┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\033[0m"
echo -e "\033[1;36m┃ \033[1;32m🟢 On:\033[1;37m $_onlin    \033[1;31m🔴 Exp:\033[1;37m $_userexp   \033[1;34m🔵 Tot:\033[1;37m $_tuser\033[0m"
echo -e "\033[1;36m╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯\033[0m"
echo ""
echo -e "\033[1;35m[\033[1;36m1\033[1;35m] \033[1;32m◈ \033[1;37mအကောင့်ဖန်တီးရန် (CREATE ACCOUNT)"
echo -e "\033[1;35m[\033[1;36m2\033[1;35m] \033[1;32m◈ \033[1;37mအကောင့်ဖျက်ရန် (DELETE ACCOUNT)"
echo -e "\033[1;35m[\033[1;36m3\033[1;35m] \033[1;32m◈ \033[1;37mသက်တမ်းတိုးရန် / ပြင်ရန် (RENEW / EDIT ACCOUNT)"
echo -e "\033[1;35m[\033[1;36m4\033[1;35m] \033[1;32m◈ \033[1;37mအကောင့်စာရင်းစစ်ရန် (LIST USERS)"
echo -e "\033[1;35m[\033[1;36m5\033[1;35m] \033[1;32m◈ \033[1;34mAdmin သို့ ဆက်သွယ်ရန် (CONTACT ADMIN)"
echo -e "\033[1;35m[\033[1;36m6\033[1;35m] \033[1;32m◈ \033[1;33mသက်တမ်းကုန်/လွန် စာရင်း (EXPIRED LIST)\033[0m"
echo -e "\033[1;35m[\033[1;36m0\033[1;35m] \033[1;32m◈ \033[1;31mထွက်မည် (EXIT)"
echo ""
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;32m 💬 Admin Facebook : \033[1;34mhttps://www.facebook.com/share/1CFG2UQzrD/\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
read -p "➔ ရွေးချယ်ရန် နံပါတ်: " opt

case $opt in
    1) clear; echo -e "\E[44;1;37m        CREATE ZIVPN UDP ACCOUNT         \E[0m\n"; read -p "◈ Username    : " nome; [[ -z "$nome" ]] && continue; read -p "◈ Password    : " senha; read -p "◈ Expire Days : " dias; useradd -M -s /bin/false "$nome" > /dev/null 2>&1 || true; echo "$nome:$senha" | chpasswd > /dev/null 2>&1 || true; python3 -c "
import json, sys, os
from datetime import datetime, timedelta
user = '$nome'; password = '$senha'; days = int('$dias'); expires = (datetime.now() + timedelta(days=days)).strftime('%Y-%m-%d'); ufile = '/etc/zivpn/users.json'
try:
    with open(ufile, 'r') as f: users = json.load(f)
except: users = []
replaced = False
for u in users:
    if u.get('user','').lower() == user.lower(): u['password'] = password; u['expires'] = expires; replaced = True; break
if not replaced: users.append({'user':user, 'password':password, 'expires':expires})
with open(ufile+'.tmp', 'w') as f: json.dump(users, f, indent=2); os.rename(ufile+'.tmp', ufile)
"; update_zivpn; validade2=$(date '+%d/%m/%Y' -d " +$dias days"); clear; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; echo -e "\033[1;32m🚀Thu Ya Zaw🚀 ZiVPN UDPအကောင့်ဖန်တီးပြီးပါပြီခင်ဗျာ\033[0m"; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; echo -e "\033[1;31m            🔻🔻🔻🔻🔻🔻\033[0m\n"; echo -e "\033[1;33m◈📡 Host / IP   :⪧  \033[1;37m$IP\033[0m\n"; echo -e "\033[1;33m◈Domain :⪧ \033[1;37m$HOST_DOMAIN\033[0m\n"; echo -e "\033[1;33m◈🧸 Username :⪧ \033[1;37m$nome\033[0m\n"; echo -e "\033[1;33m◈🔏 Password :⪧ \033[1;37m$senha\033[0m\n"; echo -e "\033[1;33m◈🕰 Expire Date :⪧ \033[1;37m$validade2\033[0m\n"; echo -e "\033[1;36m           ◈Facebook :⪧လင့်◈\033[0m"; echo -e "\033[1;32m            🔰🔰🔰🔰🔰🔰🔰\033[0m"; echo -e "\033[1;34m https://www.facebook.com/share/1CFG2UQzrD/ \033[0m"; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; read -n 1 -s -r -p "Press any key to return..." ;;
    2) clear; echo -e "\E[41;1;37m        DELETE ZIVPN UDP ACCOUNT         \E[0m\n"; show_account_table; echo ""; read -p "➔ ဖျက်လိုသော အကောင့်နံပါတ်ကို ရွေးပါ : " num; [[ -z "$num" ]] && continue; if [[ "$num" =~ ^[0-9]+$ ]]; then deleted_user=$(python3 <<EOF
import json, os
ufile = '/etc/zivpn/users.json'
try:
    with open(ufile, 'r') as f: users = json.load(f)
    idx = int('$num') - 1
    if 0 <= idx < len(users):
        user = users[idx].get('user'); new_users = [u for i, u in enumerate(users) if i != idx]
        with open(ufile+'.tmp', 'w') as f: json.dump(new_users, f, indent=2); os.rename(ufile+'.tmp', ufile); print(user)
    else: print('INVALID')
except: print('ERROR')
EOF
); if [[ "$deleted_user" != "INVALID" && "$deleted_user" != "ERROR" ]]; then update_zivpn; userdel "$deleted_user" > /dev/null 2>&1 || true; echo -e "\n\033[1;32m✅ Account '$deleted_user' ကို အောင်မြင်စွာ ဖျက်ပစ်လိုက်ပါပြီ!\033[0m"; else echo -e "\n\033[1;31mနံပါတ်မှားယွင်းနေပါသည်။\033[0m"; fi; read -n 1 -s -r -p "Press any key to return..."; fi ;;
    3) clear; echo -e "\E[42;1;37m      RENEW / EDIT ZIVPN UDP ACCOUNT       \E[0m\n"; show_account_table; echo ""; read -p "➔ ပြင်ဆင်လိုသော နံပါတ်ရိုက်ထည့်ပါ : " num; [[ -z "$num" ]] && continue; if [[ "$num" =~ ^[0-9]+$ ]]; then echo -e "\n\033[1;36m[မှတ်ချက်] - ရက်ပေါင်း (ဥပမာ 30) (သို့) ရက်စွဲအတိအကျ (ဥပမာ 5-4-2026) ရိုက်ထည့်နိုင်ပါတယ်။\033[0m"; echo -e "\033[1;33m👇 တိုးလိုသော ရက် (သို့) ရက်စွဲ အတိအကျကို အောက်တွင် ရိုက်ထည့်ပါ 👇\033[0m"; read -p "➔ ရိုက်ထည့်ရန် : " dias; [[ -z "$dias" ]] && continue; renewed_user=$(python3 <<EOF
import json, os
from datetime import datetime, timedelta
ufile = '/etc/zivpn/users.json'
try:
    with open(ufile, 'r') as f: users = json.load(f)
    idx = int('$num') - 1
    if 0 <= idx < len(users):
        user = users[idx].get('user'); input_val = '$dias'.strip().replace('/', '-')
        if '-' in input_val:
            parts = input_val.split('-')
            try:
                new_exp = datetime.strptime(input_val, '%Y-%m-%d').strftime('%Y-%m-%d') if len(parts[0]) == 4 else datetime.strptime(input_val, '%d-%m-%Y').strftime('%Y-%m-%d')
                users[idx]['expires'] = new_exp
            except: print('INVALID_DATE'); exit(0)
        else:
            days = int(input_val); old_exp = users[idx].get('expires', datetime.now().strftime('%Y-%m-%d'))
            try:
                dt = datetime.strptime(old_exp, '%Y-%m-%d'); dt = datetime.now() if dt.date() < datetime.now().date() else dt
            except: dt = datetime.now()
            new_exp = (dt + timedelta(days=days)).strftime('%Y-%m-%d'); users[idx]['expires'] = new_exp
        with open(ufile+'.tmp', 'w') as f: json.dump(users, f, indent=2); os.rename(ufile+'.tmp', ufile); print(f"{user}|{new_exp}")
    else: print('INVALID')
except: print('ERROR')
EOF
); if [[ "$renewed_user" == "INVALID_DATE" ]]; then echo -e "\n\033[1;31mရက်စွဲ ပုံစံမှားယွင်းနေပါသည်။\033[0m"; elif [[ "$renewed_user" != "INVALID" && "$renewed_user" != "ERROR" && -n "$renewed_user" ]]; then update_zivpn; user_name=$(echo "$renewed_user" | cut -d'|' -f1); new_date=$(echo "$renewed_user" | cut -d'|' -f2); echo -e "\n\033[1;32m✅ Account '$user_name' ကို ($new_date) အထိ သက်တမ်းတိုးပြီးပါပြီ!\033[0m"; else echo -e "\n\033[1;31mအချက်အလက် မှားယွင်းနေပါသည်။\033[0m"; fi; read -n 1 -s -r -p "Press any key to return..."; fi ;;
    4) clear; echo -e "\E[44;1;37m                   ZIVPN ACCOUNT LIST                   \E[0m\n"; python3 -c "
import json; from datetime import datetime
try:
    with open('/etc/zivpn/users.json', 'r') as f: users = json.load(f)
    total = len(users)
except: users = []; total = 0
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
print('\033[1;32m 📊 စုစုပေါင်း အကောင့်အရေအတွက် : \033[1;33m{} \033[1;32mယောက်\033[0m'.format(total))
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
" ; show_account_table; echo ""; read -n 1 -s -r -p "Press any key to return..." ;;
    5) clear; echo -e "\E[44;1;37m                   CONTACT ADMIN                    \E[0m\n"; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; echo -e "\033[1;32m 💬 အခက်အခဲတစ်စုံတစ်ရာရှိပါက အောက်ပါ Link မှတစ်ဆင့်\n    Admin သို့ တိုက်ရိုက်ဆက်သွယ်နိုင်ပါသည်။\033[0m"; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"; echo -e "\033[1;33m ◈ Facebook :\033[1;34m https://www.facebook.com/share/1CFG2UQzrD/\033[0m\n"; echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"; read -n 1 -s -r -p "Press any key to return..." ;;
    6) clear; echo -e "\E[41;1;37m             EXPIRED / EXPIRING TODAY LIST              \E[0m\n"; python3 -c "
import json; from datetime import datetime
try:
    with open('/etc/zivpn/users.json', 'r') as f: users = json.load(f)
except: users = []
expired_users = []; today = datetime.now().date()
for u in users:
    exp = u.get('expires', '')
    if exp:
        try:
            exp_date = datetime.strptime(exp.strip(), '%Y-%m-%d').date()
            if exp_date <= today: expired_users.append((u.get('user', ''), exp, exp_date))
        except: pass
total = len(expired_users)
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
print('\033[1;31m 🔴 သက်တမ်းကုန်/လွန် စုစုပေါင်း : \033[1;33m{} \033[1;31mယောက်\033[0m'.format(total))
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
print('\033[1;33m{:<3}| {:<15} | {:<12} | {}\033[0m'.format('NO', 'USERNAME', 'EXPIRES', 'STATUS'))
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
if not expired_users: print('\033[1;32m   ယနေ့ကုန်မည့် (သို့) သက်တမ်းလွန်နေသော အကောင့်မရှိပါ။\033[0m')
else:
    for i, (user, exp, exp_date) in enumerate(expired_users, 1):
        if exp_date < today: print('\033[1;35m{:02d} \033[1;36m|\033[1;31m {:<15} \033[1;36m|\033[1;37m {:<12} \033[1;36m|\033[1;31m 🔴 သက်တမ်းလွန်\033[0m'.format(i, user[:15], exp))
        else: print('\033[1;35m{:02d} \033[1;36m|\033[1;33m {:<15} \033[1;36m|\033[1;37m {:<12} \033[1;36m|\033[1;33m ⚠️ ယနေ့ကုန်မည်\033[0m'.format(i, user[:15], exp))
print('\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m')
"; echo ""; read -n 1 -s -r -p "Press any key to return..." ;;
    0) clear; exit 0 ;;
    *) echo -e "\n\033[1;31mမှားယွင်းနေပါသည်။ ပြန်ရွေးပါ။\033[0m"; sleep 1 ;;
esac
done
