terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Bootstrap creates the state bucket, so its own state starts on disk.
  # After the first apply you may move it into the bucket: uncomment, then run
  #   terraform init -migrate-state -backend-config=../envs/backend.hcl
  #
  # backend "s3" {
  #   key = "bootstrap/terraform.tfstate"
  # }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "HiveConnect"
      Env       = "shared"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
