variable "name" {
  description = "リソース名の接頭辞（例: aws-iac-monitoring-dev）"
  type        = string
}

variable "alarm_email" {
  description = "アラートの通知を受け取るメールアドレス。terraform.tfvars に書き、リポジトリには入れない"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email にはメールアドレスを指定してください。"
  }
}

variable "instance_ids" {
  description = "監視する EC2。役割名 → インスタンス ID"
  type        = map(string)
}

variable "zabbix_publisher_role_name" {
  description = "Zabbix から SNS へ通知を送るインスタンスの IAM ロール名（monitor のロール）"
  type        = string
}

variable "cpu_threshold_percent" {
  description = "CPU 使用率のアラームのしきい値（5分間の平均、%）"
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_threshold_percent > 0 && var.cpu_threshold_percent <= 100
    error_message = "cpu_threshold_percent は 0 より大きく 100 以下にしてください。"
  }
}
