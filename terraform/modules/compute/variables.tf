variable "name" {
  description = "リソース名の接頭辞（例: aws-iac-monitoring-dev）"
  type        = string
}

variable "subnet_id" {
  description = "EC2 を置くサブネットの ID"
  type        = string
}

variable "instances" {
  description = <<-EOT
    作る EC2 の定義。キーが役割名になり、タグ Role とリソース名に使われる。
    Ansible の動的インベントリは、このタグ Role でグループを分ける。
  EOT

  type = map(object({
    instance_type      = string
    root_volume_gb     = number
    security_group_ids = list(string)
  }))

  validation {
    condition     = alltrue([for k, v in var.instances : v.root_volume_gb >= 8])
    error_message = "root_volume_gb は 8 以上にしてください（Amazon Linux 2023 の AMI が 8GB のため）。"
  }
}
