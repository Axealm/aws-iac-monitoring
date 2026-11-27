# セキュリティグループ。
# - 22 番（SSH）はどちらにも開けない。接続は SSM Session Manager を使う。
# - 外向きは HTTPS（443）と、Zabbix の通信に必要なポートだけに絞る。
# - DNS・時刻同期（169.254.169.123）・メタデータは、セキュリティグループの対象外なので書かない。
# description は AWS 側の制約で英数字と一部の記号しか使えないため、英語で書く。

resource "aws_security_group" "monitor" {
  #checkov:skip=CKV2_AWS_5:誤検知。EC2 への割り当ては compute モジュールで行っており、checkov がモジュールをまたいで追えない
  name        = "${var.name}-monitor"
  description = "Zabbix server. No inbound from the internet."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name}-monitor"
  }
}

resource "aws_security_group" "web" {
  #checkov:skip=CKV2_AWS_5:誤検知。EC2 への割り当ては compute モジュールで行っており、checkov がモジュールをまたいで追えない
  name        = "${var.name}-web"
  description = "Web server. HTTP only from allowed client CIDRs and the monitor."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name}-web"
  }
}

# --- monitor: 受信 ---

resource "aws_vpc_security_group_ingress_rule" "monitor_zabbix_trapper_from_web" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "Zabbix agent (active checks) from web"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 10051
  to_port                      = 10051
}

# --- monitor: 送信 ---

resource "aws_vpc_security_group_egress_rule" "monitor_https" {
  security_group_id = aws_security_group.monitor.id
  description       = "HTTPS to AWS APIs (SSM, SNS) and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "monitor_zabbix_agent_to_web" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "Zabbix passive checks to web"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 10050
  to_port                      = 10050
}

resource "aws_vpc_security_group_egress_rule" "monitor_http_to_web" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "HTTP checks (Zabbix web scenario) to web"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# --- web: 受信 ---

resource "aws_vpc_security_group_ingress_rule" "web_http_from_allowed" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTP from an allowed client CIDR"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_http_from_monitor" {
  #checkov:skip=CKV_AWS_260:誤検知。送信元は monitor のセキュリティグループで、0.0.0.0/0 ではない
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP checks (Zabbix web scenario) from monitor"
  referenced_security_group_id = aws_security_group.monitor.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_zabbix_agent_from_monitor" {
  security_group_id            = aws_security_group.web.id
  description                  = "Zabbix passive checks from monitor"
  referenced_security_group_id = aws_security_group.monitor.id
  ip_protocol                  = "tcp"
  from_port                    = 10050
  to_port                      = 10050
}

# --- web: 送信 ---

resource "aws_vpc_security_group_egress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to AWS APIs (SSM) and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "web_zabbix_trapper_to_monitor" {
  security_group_id            = aws_security_group.web.id
  description                  = "Zabbix agent (active checks) to monitor"
  referenced_security_group_id = aws_security_group.monitor.id
  ip_protocol                  = "tcp"
  from_port                    = 10051
  to_port                      = 10051
}
