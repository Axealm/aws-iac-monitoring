#!/usr/bin/env bash
# 開発に使うツールを Ubuntu（WSL2）に入れる。root で実行する。
#
#   sudo bash scripts/dev/install-tools-root.sh
#   （WSL で sudo を使わない場合: wsl -u root -e bash scripts/dev/install-tools-root.sh）
#
# - 配布元はすべて各ツールの公式。版を固定し、チェックサムが公開されているものは照合する。
# - Ubuntu 公式の配布サーバーが応答しないときは、APT_MIRROR にミラーの URL を指定する。
#   その実行のときだけ取得元が変わり、/etc/apt の設定は書き換えない。
#   パッケージの署名は Ubuntu の鍵で検証される。経緯は docs/work-log.md の 4 を参照。
#
#   sudo APT_MIRROR=https://ftp.riken.jp/Linux/ubuntu bash scripts/dev/install-tools-root.sh
set -euo pipefail

TERRAFORM_VERSION="1.17.2"
TFLINT_VERSION="v0.66.0"
GITLEAKS_VERSION="8.30.1"

export DEBIAN_FRONTEND=noninteractive

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

APT_OPTS=(-o Acquire::ForceIPv4=true -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20
          -o Acquire::Retries=3 -o Acquire::Languages=none)

if [ -n "${APT_MIRROR:-}" ]; then
  echo "== apt (ミラー: ${APT_MIRROR}) =="
  # shellcheck disable=SC1091
  . /etc/os-release
  KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
  for suite in "${VERSION_CODENAME}" "${VERSION_CODENAME}-updates" "${VERSION_CODENAME}-security"; do
    echo "deb [signed-by=${KEYRING}] ${APT_MIRROR} ${suite} main universe"
  done > "$TMP/mirror.list"
  APT_OPTS+=(-o "Dir::Etc::sourcelist=$TMP/mirror.list" -o "Dir::Etc::sourceparts=/dev/null")
else
  echo "== apt (Ubuntu の既定の取得元) =="
fi

# 進み具合が見えるように -qq は使わず、止まったら気づけるように制限時間を付ける
timeout 180 apt-get "${APT_OPTS[@]}" update -q
timeout 300 apt-get "${APT_OPTS[@]}" install -y -q unzip pipx python3-venv

echo "== Terraform ${TERRAFORM_VERSION} (releases.hashicorp.com) =="
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
grep " terraform_${TERRAFORM_VERSION}_linux_amd64.zip\$" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" | sha256sum -c -
unzip -q -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" terraform -d /usr/local/bin

echo "== AWS CLI v2 (awscli.amazonaws.com) =="
curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q awscliv2.zip
./aws/install --update >/dev/null

echo "== Session Manager plugin (s3.amazonaws.com/session-manager-downloads) =="
curl -fsSLo session-manager-plugin.deb "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
dpkg -i session-manager-plugin.deb >/dev/null

echo "== tflint ${TFLINT_VERSION} (github.com/terraform-linters/tflint) =="
curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip"
curl -fsSLo tflint_checksums.txt "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/checksums.txt"
grep " tflint_linux_amd64.zip\$" tflint_checksums.txt | sha256sum -c -
unzip -q -o tflint_linux_amd64.zip tflint -d /usr/local/bin

echo "== gitleaks ${GITLEAKS_VERSION} (github.com/gitleaks/gitleaks) =="
curl -fsSLO "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
curl -fsSLO "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"
grep " gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz\$" "gitleaks_${GITLEAKS_VERSION}_checksums.txt" | sha256sum -c -
tar -xzf "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -C /usr/local/bin gitleaks

chmod 755 /usr/local/bin/terraform /usr/local/bin/tflint /usr/local/bin/gitleaks

echo "== 入った版 =="
# pipefail のもとで head を使うと SIGPIPE（終了コード 141）になるので、sed で1行目だけ表示する
terraform version | sed -n 1p
aws --version
session-manager-plugin --version
tflint --version | sed -n 1p
gitleaks version
