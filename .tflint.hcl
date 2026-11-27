# tflint の設定。リポジトリの直下で次のように実行する。
#
#   tflint --init
#   tflint --chdir=terraform --recursive --config "$(pwd)/.tflint.hcl"

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
