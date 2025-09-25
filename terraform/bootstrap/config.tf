terraform {
  backend "s3" {
    bucket = "meyerkev-terraform-state"
    key    = "bootstrap-ecr.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.34"
    }
  }
  required_version = "~> 1.13.3"
}

provider "aws" {
  region = var.region
}
