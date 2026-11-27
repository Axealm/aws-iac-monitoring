# dev 環境。network・compute・monitoring のモジュールを組み合わせる。

locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  availability_zone  = var.availability_zone
  allowed_http_cidrs = var.allowed_http_cidrs
}

module "compute" {
  source = "../../modules/compute"

  name      = local.name
  subnet_id = module.network.public_subnet_id

  # キー（monitor / web）がタグ Role になり、Ansible の動的インベントリのグループになる
  instances = {
    monitor = {
      instance_type      = var.monitor_instance_type
      root_volume_gb     = 16
      security_group_ids = [module.network.monitor_security_group_id]
    }
    web = {
      instance_type      = var.web_instance_type
      root_volume_gb     = 8
      security_group_ids = [module.network.web_security_group_id]
    }
  }
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                       = local.name
  alarm_email                = var.alarm_email
  instance_ids               = module.compute.instance_ids
  zabbix_publisher_role_name = module.compute.iam_role_names["monitor"]
}
