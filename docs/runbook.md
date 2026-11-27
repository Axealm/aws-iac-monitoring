# 運用手順書（runbook）

アラートが届いたときに、何を確認して、どう復旧するかの手順。
個人の学習・検証用の環境のもので、本番運用の実績に基づくものではない。nginx・chronyd・おみくじ API・CPU の手順は、障害注入テスト（[fault-injection.md](fault-injection.md)）で実際に試した。それ以外は、試していないことを明記している。

## 共通: サーバーへの入り方

SSH は使わない（sshd は止めてあり、22 番も開けていない）。SSM Session Manager で入る。

```bash
# 接続コマンドを表示する
terraform -chdir=terraform/envs/dev output ssm_start_session_commands

# 1 行のコマンドを実行して結果だけ見る
echo 'systemctl status nginx --no-pager' | bash scripts/dev/ssm-run.sh web
```

Zabbix の画面は、ポート転送を張って手元のブラウザーで見る。

```bash
# 張っている間、http://localhost:18080/ で Zabbix が開く（Ctrl+C で閉じる）
bash scripts/dev/zabbix-forward.sh sleep 3600

# 今の状態を文字で見る
bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py status
```

## アラートの一覧

| アラート | 出どころ | 深刻度 | 手順 |
|---|---|---|---|
| nginx is not running | Zabbix | 重度 | [nginx](#nginx) |
| HTTP check of /omikuji failed | Zabbix | 重度 | [HTTP の監視](#http-の監視) |
| /omikuji returns 502 | Zabbix | 重度 | [おみくじ API](#おみくじ-api) |
| omikuji API is not running | Zabbix | 重度 | [おみくじ API](#おみくじ-api) |
| chronyd is not running | Zabbix | 重度 | [chronyd](#chronyd) |
| CPU utilization is above 80% for 2 minutes | Zabbix | 警告 | [CPU](#cpu) |
| ...-cpu-high | CloudWatch | - | [CPU](#cpu) |
| ...-status-check-failed | CloudWatch | - | [ステータスチェック](#ステータスチェック) |
| Zabbix agent is not available（標準テンプレート） | Zabbix | 軽度 | [エージェントに届かない](#エージェントに届かない) |

## まず見ること

アラートは組み合わせで届く。1 通ずつ対応する前に、同じ時刻に何が出ているかを見る。

| 出ているアラート | 考えられる原因 |
|---|---|
| nginx + HTTP の監視 | nginx が止まった |
| おみくじ API + 502 + HTTP の監視（nginx のアラートはない） | 裏の API だけが止まった |
| HTTP の監視だけ | 監視サーバーから web への通信の問題、または nginx の設定の問題 |
| エージェントに届かない + ステータスチェック | サーバー自体が応答していない |
| エージェントに届かない だけ | エージェントが止まった、または 10050 番の通信の問題 |

## nginx

**確認**

```bash
bash scripts/dev/ssm-run.sh web <<'EOF'
systemctl status nginx --no-pager | head -15
journalctl -u nginx -n 30 --no-pager
nginx -t
EOF
```

**復旧**

1. 設定に誤りがある場合（`nginx -t` が失敗する）は、設定を直す。設定は Ansible が管理しているので、`ansible/roles/web/templates/nginx.conf.j2` を直して `ansible-playbook site.yml --limit web` を実行する。サーバーの上で直接書き換えない。
2. 止まっているだけなら起動する。

```bash
echo 'systemctl start nginx' | bash scripts/dev/ssm-run.sh web
```

**解消の確認**: 30 秒ほどで Zabbix のアラートが解消し、復旧のメールが届く。

## おみくじ API

`/omikuji returns 502` は、nginx は動いているが、裏の API（`omikuji.service`）に中継できない状態。

**確認**

```bash
bash scripts/dev/ssm-run.sh web <<'EOF'
systemctl status omikuji --no-pager | head -15
journalctl -u omikuji -n 30 --no-pager
curl -s -m 5 http://127.0.0.1:8000/healthz
ss -ltn | grep 8000
EOF
```

**復旧**

```bash
echo 'systemctl start omikuji' | bash scripts/dev/ssm-run.sh web
```

落ちる原因がコードにある場合は、`app/omikuji/omikuji.py` を直してテスト（`python3 -m unittest discover -s app/omikuji`）を通し、`ansible-playbook site.yml --limit web` で配り直す。systemd は異常終了のときだけ自動で再起動する（`Restart=on-failure`）。`systemctl stop` で止めた場合は、自動では戻らない。

## HTTP の監視

監視サーバーから `http://<web のプライベート IP>/omikuji` を取得して、200 が返ることと、本文に `result` が含まれることを見ている。

**確認**

```bash
# web の中から
echo 'curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://127.0.0.1/omikuji' | bash scripts/dev/ssm-run.sh web

# 監視サーバーから（Zabbix と同じ経路）
terraform -chdir=terraform/envs/dev output private_ips
echo 'curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://<web のプライベート IP>/omikuji' | bash scripts/dev/ssm-run.sh monitor
```

- web の中からは 200 で、監視サーバーからは届かない場合: セキュリティグループ（monitor → web の 80 番）を確認する。Terraform で管理しているので、`terraform plan` で差分が出ないかを見る。
- web の中からも 200 でない場合: [nginx](#nginx) と [おみくじ API](#おみくじ-api) を確認する。

## chronyd

時刻がずれると、ログの突き合わせや認証（AWS の API は時刻のずれに厳しい）に影響する。

**確認**

```bash
bash scripts/dev/ssm-run.sh web <<'EOF'
systemctl status chronyd --no-pager | head -12
chronyc tracking
chronyc -n sources
EOF
```

**復旧**

```bash
echo 'systemctl start chronyd' | bash scripts/dev/ssm-run.sh web
```

起動後に `chronyc tracking` の `Leap status` が `Normal` で、`System time` のずれが小さいことを確認する。参照先は Amazon Time Sync Service（`169.254.169.123`）。

## CPU

Zabbix は 2 分間の平均が 80% を超えると発報する。CloudWatch は 5 分間の平均が 80% 以上で発報する。

**確認**

```bash
bash scripts/dev/ssm-run.sh web <<'EOF'
uptime
ps -eo pid,user,pcpu,pmem,etimes,cmd --sort=-pcpu | head -8
systemctl list-units --type=service --state=running --no-pager | head -20
EOF
```

**復旧**

1. CPU を使っているプロセスを特定する。
2. 止めてよいものであれば、そのサービスを止める（`systemctl stop <名前>`）。
3. 正当な負荷であれば、インスタンスタイプを上げる（`terraform/envs/dev/terraform.tfvars` の `web_instance_type` を変えて apply。インスタンスは作り直しになる）。

**注意**: T3 の CPU クレジットを standard にしている。負荷が続いてクレジットを使い切ると、CPU の性能が基準値（t3.micro は 1 vCPU あたり 10%）まで絞られる。このとき、OS からは CPU 使用率が高いままに見える。クレジットの残りは CloudWatch の `CPUCreditBalance` で見られる（この確認は試していない）。

## ステータスチェック

EC2 のステータスチェックが失敗した状態。ハードウェアや OS が応答していない。**このアラームは、テストで発報させていない。以下は想定の手順。**

1. AWS のコンソール（または CLI）で、どちらのチェックが失敗しているかを見る。

```bash
aws ec2 describe-instance-status --instance-ids <インスタンス ID> \
  --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' --output text
```

2. システムのチェック（AWS 側のハードウェア）が失敗している場合は、停止して起動し直すと、別のホストに移る。
3. インスタンスのチェック（OS 側）が失敗している場合は、再起動する。直らなければ作り直す。

この環境は、作り直しても `terraform apply` → `ansible-playbook site.yml` → `scripts/dev/zabbix-config.sh` で元に戻せる。直すより作り直すほうが早い場合が多い。

## エージェントに届かない

Zabbix サーバーからエージェント（10050 番）に届かない状態。**このアラートは、テストで発報させていない。以下は想定の手順。**

1. [ステータスチェック](#ステータスチェック)のアラームも出ているかを見る。出ていれば、サーバー自体の問題。
2. サーバーに SSM で入れるかを試す。

```bash
echo 'systemctl status zabbix-agent2 --no-pager | head -12' | bash scripts/dev/ssm-run.sh web
```

3. エージェントが止まっていれば起動する（`systemctl start zabbix-agent2`）。
4. 動いているのに届かない場合は、セキュリティグループ（monitor → web の 10050 番）と、エージェントの設定（`/etc/zabbix/zabbix_agent2.d/10-server.conf` の `Server=`）を確認する。

## 監視サーバー自身が止まったとき

Zabbix が止まると、Zabbix からのアラートは届かなくなる。この場合に気づけるのは、CloudWatch のアラーム（`...-monitor-status-check-failed`、`...-monitor-cpu-high`）だけ。**このケースはテストしていない。**

- 監視サーバーのサービスの確認:

```bash
echo 'systemctl is-active postgresql zabbix-server php-fpm nginx zabbix-agent2' | bash scripts/dev/ssm-run.sh monitor
```

- Zabbix サーバーのプロセスだけが止まった場合（EC2 は正常）は、CloudWatch では検知できない。これは、今の構成の弱点。外から Zabbix の画面や API を定期的に確認する仕組みが必要になる（今後の課題）。

## 通知が届かないとき

```bash
# 購読の状態を確認し、監視サーバーからテスト通知を 1 通送る
bash scripts/dev/sns-test.sh
```

- 購読が `PendingConfirmation` の場合: 確認メールのリンクを押していない。
- テスト通知が送れない場合: 監視サーバーの IAM ロールに `sns:Publish` があるか（`terraform plan` で差分を確認）、外向きの 443 番が開いているかを見る。
- テスト通知は届くのに、Zabbix のアラートが届かない場合: Zabbix の画面の「レポート → アクションログ」で、送信の失敗が出ていないかを見る。

## 作り直す

設定がおかしくなって原因が分からないときは、作り直すのが確実。

```bash
bash scripts/dev/tf-plan.sh terraform/envs/dev        # 内容を確認
bash scripts/dev/tf-apply.sh terraform/envs/dev
bash scripts/dev/ansible.sh ansible-playbook site.yml
bash scripts/dev/zabbix-config.sh
bash scripts/dev/verify-config.sh
```

Zabbix のデータベースは EC2 の中にあるので、作り直すと監視の履歴は消える。パスワードは SSM Parameter Store に残っているので、同じものが使われる。
