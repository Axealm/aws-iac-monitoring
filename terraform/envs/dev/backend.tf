# state は S3 に置く。ロックは S3 のロックファイル（use_lockfile）を使い、DynamoDB は使わない。
# バケット名にはアカウント ID が入るので、ここには書かずに backend.hcl で渡す。
#
#   terraform init -backend-config=backend.hcl

terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
