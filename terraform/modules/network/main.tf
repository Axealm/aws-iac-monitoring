# VPC・サブネット・ルート。NAT Gateway は費用がかかるので作らない。

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# VPC に最初からある default セキュリティグループは、ルールを空にして使えなくする
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-default-unused"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# --- public サブネット（EC2 を置く） ---

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  # パブリック IP は自動では付けず、EC2 の側で明示して付ける
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-public"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- private サブネット（今は EC2 を置かない） ---
# NAT Gateway なしでは外へ出られず、SSM 接続もパッケージ取得もできない。
# 将来 NAT か VPC エンドポイントを足したときの置き場所として、枠だけ作っておく。

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-private"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  # VPC 内の経路だけ（インターネットへの経路なし）

  tags = {
    Name = "${var.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
