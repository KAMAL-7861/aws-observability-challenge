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

# --- VPC (with public subnets for ALB) ---

module "vpc" {
  source = "../../modules/vpc"

  region                = var.region
  cidr_block            = var.vpc_cidr
  cluster_name          = var.cluster_name
  availability_zones    = var.availability_zones
  enable_public_subnets = true
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

# --- PrivateLink Consumer (VPC Endpoint to C2) ---

module "privatelink_consumer" {
  source = "../../modules/privatelink-consumer"

  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  endpoint_service_name = var.c2_endpoint_service_name
  service_region        = var.c2_service_region
}

# --- ALB (public-facing, targets frontend on port 8080) ---

module "alb" {
  source = "../../modules/alb"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  target_group_port = var.target_group_port
}

# --- WAF (associated with ALB) ---

module "waf" {
  source = "../../modules/waf"

  alb_arn              = module.alb.alb_arn
  rate_limit_threshold = var.waf_rate_limit
}
