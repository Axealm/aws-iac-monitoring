#!/usr/bin/env bash
# checkov を、ログインユーザーの領域（~/.local）に pipx で入れる。root は使わない。
# 先に install-tools-root.sh を実行しておく（pipx が必要）。
#
#   bash scripts/dev/install-tools-user.sh
set -euo pipefail

CHECKOV_VERSION="3.4.11"

echo "== checkov ${CHECKOV_VERSION} (pypi.org) =="
pipx install "checkov==${CHECKOV_VERSION}"
pipx ensurepath >/dev/null

echo "== 入った版 =="
"$HOME/.local/bin/checkov" --version
