variable "region" {
  description = "リソースを作るリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "プロジェクト名。リソース名とタグに使う"
  type        = string
  default     = "aws-iac-monitoring"
}

variable "budget_limit_usd" {
  description = "月額の予算（米ドル）。既定の 7 ドルは約 1,000 円"
  type        = string
  default     = "7"

  validation {
    condition     = can(tonumber(var.budget_limit_usd)) && tonumber(var.budget_limit_usd) > 0
    error_message = "budget_limit_usd には 0 より大きい数値を指定してください。"
  }
}

variable "budget_email" {
  description = "予算の通知を受け取るメールアドレス。terraform.tfvars に書き、リポジトリには入れない"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email にはメールアドレスを指定してください。"
  }
}
