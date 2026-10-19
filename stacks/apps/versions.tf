terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Settings come from envs/backend.hcl; scripts/tf.sh sets key = <env>/apps.tfstate.
  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "HiveConnect"
      Env       = var.env
      ManagedBy = "terraform"
      Stack     = "apps"
    }
  }
}
