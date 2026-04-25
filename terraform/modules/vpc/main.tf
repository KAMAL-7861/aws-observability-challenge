locals {
  # Generate private subnet CIDRs from the VPC CIDR block.
  # For a /16 VPC, this produces /20 subnets (e.g., 10.0.0.0/20, 10.0.16.0/20).
  private_subnet_cidrs = [
    for i, az in var.availability_zones :
    cidrsubnet(var.cidr_block, 4, i)
  ]

  # Public subnets are always created (needed for NAT gateway).
  # The enable_public_subnets flag controls whether they get ALB/ELB tags.
  public_subnet_cidrs = [
    for i, az in var.availability_zones :
    cidrsubnet(var.cidr_block, 4, i + length(var.availability_zones))
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.cidr_block
  azs  = var.availability_zones

  private_subnets = local.private_subnet_cidrs
  public_subnets  = local.public_subnet_cidrs

  # NAT gateway for private subnet internet access (pulling container images, etc.)
  enable_nat_gateway = true
  single_nat_gateway = true # Cost-effective for non-production

  # DNS support required for VPC endpoints and EKS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS-required tags for subnet discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  public_subnet_tags = var.enable_public_subnets ? {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  } : {}

  tags = {
    Terraform   = "true"
    Environment = var.cluster_name
  }
}
