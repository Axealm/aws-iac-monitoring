#!/usr/bin/env bash
# Ansible と、使うコレクションを入れる。root は使わない（pipx でユーザー領域に入れる）。
# 先に install-tools-root.sh を実行しておく（pipx が必要）。
#
#   bash scripts/dev/install-ansible.sh
set -euo pipefail

ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-2.22.0}"
ANSIBLE_LINT_VERSION="26.11.1"

export PATH="$HOME/.local/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"

echo "== ansible-core ${ANSIBLE_CORE_VERSION} (pypi.org) =="
pipx install --force "ansible-core==${ANSIBLE_CORE_VERSION}"
# AWS のモジュールと SSM 接続が使う。
# aws login の認証情報を boto3 から使うには、追加の依存（botocore[crt]）が要る。
# （pipx inject は、入っているパッケージの追加依存を足してくれないので、awscrt を名前で指定する）
pipx inject ansible-core boto3 botocore awscrt

echo "== ansible-lint ${ANSIBLE_LINT_VERSION} (pypi.org) =="
pipx install --force "ansible-lint==${ANSIBLE_LINT_VERSION}"

echo "== コレクション (galaxy.ansible.com) =="
ANSIBLE_CONFIG="$root/ansible/ansible.cfg" ansible-galaxy collection install \
  -r "$root/ansible/requirements.yml" -p "$root/ansible/collections"

echo "== 入った版 =="
ansible --version | sed -n 1p
ansible-lint --version | sed -n 1p
