terraform {
  # S3 だけで state をロックする use_lockfile が正式版になった 1.11 以上を前提にする
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74"
    }
  }

  # bootstrap は「state を置くバケット」そのものを作るので、ここだけ state を手元に置く。
  # 手元の terraform.tfstate は .gitignore で除外している。
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
