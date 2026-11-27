#!/usr/bin/env bash
# ansible-playbook を実行したあとの動作確認。読み取りだけを行う。
# 表示では 12桁のアカウント ID と IP アドレスを伏せる。
#
#   bash scripts/dev/verify-config.sh
set -uo pipefail

cd "$(dirname "$0")/../.."
mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/([^0-9.]|^)(1?[0-9]{1,2}|2[0-4][0-9]|25[0-5])(\.[0-9]{1,3}){3}/\1<IP>/g'; }
tf_json() { terraform -chdir=terraform/envs/dev output -json "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$2"; }
failed=0

echo "===== 1. web サーバーの中 ====="
bash scripts/dev/ssm-run.sh web <<'EOF' | mask || failed=1
for s in nginx omikuji zabbix-agent2 chronyd; do printf '%-14s %s\n' "$s" "$(systemctl is-active $s)"; done
printf '%-14s %s / %s\n' sshd "$(systemctl is-active sshd)" "$(systemctl is-enabled sshd)"
printf '%-14s %s\n' timezone "$(timedatectl show -p Timezone --value)"
printf '%-14s %s\n' /healthz "$(curl -s -m 5 http://127.0.0.1/healthz)"
printf '%-14s %s\n' /omikuji "$(curl -s -m 5 http://127.0.0.1/omikuji)"
printf '%-14s %s\n' chrony "$(chronyc tracking | sed -n 's/^Leap status *: //p') / $(chronyc -n sources | grep -c '^\^\*') 個の同期先を選択中"
# 期待する状態と違えば失敗にする
[ "$(systemctl is-active nginx omikuji zabbix-agent2 chronyd | sort -u)" = active ] || exit 1
[ "$(systemctl is-active sshd)" != active ] || exit 1
curl -fs -m 5 http://127.0.0.1/omikuji | grep -q '"result"' || exit 1
EOF

echo "===== 2. monitor サーバーの中 ====="
bash scripts/dev/ssm-run.sh monitor <<'EOF' | mask || failed=1
for s in postgresql zabbix-server php-fpm nginx zabbix-agent2 chronyd; do printf '%-14s %s\n' "$s" "$(systemctl is-active $s)"; done
printf '%-14s %s / %s\n' sshd "$(systemctl is-active sshd)" "$(systemctl is-enabled sshd)"
printf '%-14s %s\n' "web 画面" "HTTP $(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:8080/)"
api() { curl -s -m 10 -H 'Content-Type: application/json' -d "$1" http://127.0.0.1:8080/api_jsonrpc.php; }
printf '%-14s %s\n' "API の版" "$(api '{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}')"
initial="$(api '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}')"
if echo "$initial" | grep -q '"result"'; then
  echo "初期パスワード   まだ使える（変更されていない）"; bad=1
else
  echo "初期パスワード   使えない（変更済み）"; bad=0
fi
printf '%-14s %s\n' "待ち受け" "$(ss -ltnH | awk '{print $4}' | sort -u | tr '\n' ' ')"
printf '%-14s %s\n' "DB エラー" "$(grep -c -i 'database is down\|cannot connect to the database' /var/log/zabbix/zabbix_server.log) 件"
[ "$(systemctl is-active postgresql zabbix-server php-fpm nginx zabbix-agent2 chronyd | sort -u)" = active ] || exit 1
[ "$bad" = 0 ] || exit 1
EOF

echo "===== 3. 外から（この PC から）おみくじ API ====="
web_ip="$(tf_json public_ips web)"
out="$(curl -s -m 10 -w '\nHTTP %{http_code}' "http://${web_ip}/omikuji")"
echo "$out" | mask
echo "$out" | grep -q 'HTTP 200' || failed=1

echo "===== 4. Zabbix の Web 画面（SSM のポート転送） ====="
monitor_id="$(tf_json instance_ids monitor)"
aws ssm start-session --target "$monitor_id" --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=8080,localPortNumber=18080' > /tmp/pf.log 2>&1 &
pf=$!
code=000
for i in $(seq 1 15); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:18080/ || true)"
  [ "$code" = 200 ] && break
  sleep 2
done
echo "http://127.0.0.1:18080/ -> HTTP $code"
kill "$pf" 2>/dev/null
pkill -f "session-manager-plugin.*${monitor_id}" 2>/dev/null
[ "$code" = 200 ] || failed=1

echo
[ "$failed" -eq 0 ] && echo "確認結果: 問題なし" || echo "確認結果: 失敗した項目あり"
exit "$failed"
