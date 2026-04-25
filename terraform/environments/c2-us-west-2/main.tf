terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# --- VPC (private subnets only, no public subnets needed for C2) ---

module "vpc" {
  source = "../../modules/vpc"

  region               = var.region
  cidr_block           = var.vpc_cidr
  cluster_name         = var.cluster_name
  availability_zones   = var.availability_zones
  enable_public_subnets = false
}

# --- EKS Cluster ---

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_count         = var.node_count
}

# --- PrivateLink Provider (NLB + Endpoint Service) ---

module "privatelink_provider" {
  source = "../../modules/privatelink-provider"

  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  service_port           = var.service_port
  node_port              = var.node_port
  allowed_principals     = var.allowed_principals
  node_security_group_id = module.eks.node_security_group_id
  supported_regions      = ["us-west-2", "us-east-1"]
}
