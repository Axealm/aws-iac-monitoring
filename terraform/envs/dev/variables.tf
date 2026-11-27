variable "region" {
  description = "リソースを作るリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "availability_zone" {
  description = "サブネットを置くアベイラビリティゾーン"
  type        = string
  default     = "ap-northeast-1a"
}

variable "project" {
  description = "プロジェクト名。リソース名とタグに使う"
  type        = string
  default     = "aws-iac-monitoring"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "dev"
}

variable "allowed_http_cidrs" {
  description = "web サーバーの 80 番に接続を許可する CIDR のリスト（自分のグローバル IP を /32 で）。空なら外からは接続できない"
  type        = list(string)
  default     = []
}

variable "monitor_instance_type" {
  description = "監視サーバー（Zabbix Server + PostgreSQL）のインスタンスタイプ"
  type        = string
  default     = "t3.small"
}

variable "web_instance_type" {
  description = "Web サーバー（nginx + おみくじ API）のインスタンスタイプ"
  type        = string
  default     = "t3.micro"
}
