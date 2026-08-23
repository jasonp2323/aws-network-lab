terraform {
  required_version = ">= 1.9.0"

  # No `cloud` or `backend` block, deliberately.
  #
  # This root module creates the IAM OIDC provider and role that HCP Terraform
  # assumes in order to authenticate to AWS at all. A workspace cannot create
  # the credential it needs in order to run. So bootstrap/ runs from a laptop
  # against LOCAL state, once, and its state file is gitignored.
  #
  # Do not "fix" this by adding a cloud backend.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
