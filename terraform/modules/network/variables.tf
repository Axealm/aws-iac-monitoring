variable "name" {
  description = "リソース名の接頭辞（例: aws-iac-monitoring-dev）"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr には CIDR（例: 10.0.0.0/16）を指定してください。"
  }
}

variable "public_subnet_cidr" {
  description = "public サブネットの CIDR"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr には CIDR を指定してください。"
  }
}

variable "private_subnet_cidr" {
  description = "private サブネットの CIDR"
  type        = string
  default     = "10.0.11.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr には CIDR を指定してください。"
  }
}

variable "availability_zone" {
  description = "サブネットを置くアベイラビリティゾーン"
  type        = string
}

variable "allowed_http_cidrs" {
  description = "web サーバーの 80 番に接続を許可する CIDR のリスト。空なら外からは接続できない"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_http_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_http_cidrs の各要素には CIDR（例: 203.0.113.10/32）を指定してください。"
  }

  validation {
    condition     = !contains(var.allowed_http_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0（全世界への公開）は指定できません。自分の IP を /32 で指定してください。"
  }
}
