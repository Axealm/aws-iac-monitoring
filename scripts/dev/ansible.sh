#!/usr/bin/env bash
# Ansible のコマンドを、このリポジトリの設定で実行するための入口。
#
#   bash scripts/dev/ansible.sh ansible-inventory --graph
#   bash scripts/dev/ansible.sh ansible all -m ansible.builtin.ping
#   bash scripts/dev/ansible.sh ansible-playbook site.yml
#
# - WSL から Windows 側のフォルダ（/mnt/c/...）を使うと、Ansible は「誰でも書き込めるフォルダ」と
#   みなして ansible.cfg を読まない。そのため ANSIBLE_CONFIG で明示する。
# - SSM 接続が使う転送用バケットの名前（アカウント ID を含む）を、Terraform の出力から取って渡す。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
export ANSIBLE_CONFIG="$root/ansible/ansible.cfg"
export ANSIBLE_SSM_BUCKET="${ANSIBLE_SSM_BUCKET:-$(terraform -chdir="$root/terraform/envs/dev" output -raw ansible_ssm_bucket_name)}"
# Zabbix のアラートの通知先（SNS トピック。ARN にアカウント ID が入るので、ここで渡す）
export ALERT_SNS_TOPIC_ARN="${ALERT_SNS_TOPIC_ARN:-$(terraform -chdir="$root/terraform/envs/dev" output -raw sns_topic_arn)}"

cd "$root/ansible"
exec "$@"
