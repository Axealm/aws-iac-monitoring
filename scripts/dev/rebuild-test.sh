#!/usr/bin/env bash
# 通しの確認。今の dev 環境を消して、一から作り直し、設定・確認・障害注入までを続けて実行する。
# 「terraform apply と ansible-playbook で再現できる」ことを確かめるためのもの。
#
#   bash scripts/dev/rebuild-test.sh
#
# - EC2 を作り直すので、費用（起動している時間の分）がかかる。
# - 途中で失敗したら、そこで止まる（調べられるように、環境は消さずに残す）。
# - 最後の destroy は、このスクリプトでは行わない。結果を見てから別に実行する。
set -uo pipefail

cd "$(dirname "$0")/../.."
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/\x1b\[[0-9;]*m//g'; }
start=$(date +%s)
step() { echo; echo "########## [$(date +%H:%M:%S) +$(( ($(date +%s) - start) / 60 ))分] $*"; }
die() { echo "!!!!! 失敗: $*"; exit 1; }
recap() { grep -E 'unreachable=' "$1" | mask; }

step "1. 今の環境を消す（terraform destroy）"
terraform -chdir=terraform/envs/dev destroy -auto-approve -input=false -no-color > /tmp/rb-destroy.log 2>&1 \
  || { tail -20 /tmp/rb-destroy.log | mask; die "destroy"; }
grep -E 'Destroy complete' /tmp/rb-destroy.log

step "2. 一から作る（terraform plan → apply）"
bash scripts/dev/tf-plan.sh terraform/envs/dev > /tmp/rb-plan.log 2>&1 || { tail -20 /tmp/rb-plan.log; die "plan"; }
grep -E '^Plan:' /tmp/rb-plan.log
bash scripts/dev/tf-apply.sh terraform/envs/dev > /tmp/rb-apply.log 2>&1 || { tail -20 /tmp/rb-apply.log; die "apply"; }
grep -E 'Apply complete' /tmp/rb-apply.log

step "3. インフラの確認（verify-infra.sh）"
bash scripts/dev/verify-infra.sh > /tmp/rb-verify-infra.log 2>&1 || { tail -30 /tmp/rb-verify-infra.log; die "verify-infra"; }
grep -E '結果:|22番を含む|ロックファイル|確認結果' /tmp/rb-verify-infra.log

step "4. 設定を入れる（ansible-playbook site.yml）"
bash scripts/dev/ansible.sh ansible-playbook site.yml > /tmp/rb-site1.log 2>&1 \
  || { mask < /tmp/rb-site1.log | grep -E 'fatal|ERROR|msg:' -B2 | tail -30; die "site.yml"; }
recap /tmp/rb-site1.log

step "5. Zabbix の監視設定を入れる（zabbix-config.yml）"
bash scripts/dev/zabbix-config.sh > /tmp/rb-zc1.log 2>&1 \
  || { mask < /tmp/rb-zc1.log | grep -E 'fatal|ERROR|msg:' -B2 | tail -30; die "zabbix-config"; }
recap /tmp/rb-zc1.log

step "6. 冪等性（もう一度実行して changed=0）"
bash scripts/dev/ansible.sh ansible-playbook site.yml > /tmp/rb-site2.log 2>&1 || die "site.yml（2回目）"
recap /tmp/rb-site2.log
bash scripts/dev/zabbix-config.sh > /tmp/rb-zc2.log 2>&1 || die "zabbix-config（2回目）"
recap /tmp/rb-zc2.log
if grep -E 'unreachable=' /tmp/rb-site2.log /tmp/rb-zc2.log | grep -v -q 'changed=0 '; then
  die "2回目の実行で changed が 0 にならなかった"
fi

step "7. 設定の確認（verify-config.sh）"
bash scripts/dev/verify-config.sh > /tmp/rb-verify-config.log 2>&1 || { tail -40 /tmp/rb-verify-config.log; die "verify-config"; }
grep -E 'active|HTTP|初期パスワード|確認結果' /tmp/rb-verify-config.log | mask

step "8. 監視が落ち着くのを待つ（起動直後の一時的なアラートが消えるまで）"
for i in $(seq 1 40); do
  n="$(bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py problems 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo '?')"
  echo "  $(date +%H:%M:%S) 発生中の障害: $n 件"
  [ "$n" = "0" ] && break
  sleep 30
done
[ "$n" = "0" ] || { bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py status | tail -8; die "発生中の障害が 0 件にならない"; }
bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py status | mask || die "Zabbix で値が取れていない"

step "9. 障害注入テスト（nginx、chronyd、おみくじ API）"
bash scripts/fault-injection/run-all.sh || die "障害注入テスト"

step "完了。通しの確認はすべて成功（環境は残してある。destroy は別に実行する）"
