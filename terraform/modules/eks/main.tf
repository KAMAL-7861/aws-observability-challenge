module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  # Match existing cluster setting to prevent forced replacement
  bootstrap_self_managed_addons = false

  # Cluster endpoint access: private enabled, public enabled with CIDR allowlisting
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  # Enable IRSA (IAM Roles for Service Accounts) via OIDC provider
  enable_irsa = true

  # Managed node group — workers in private subnets, no public IP
  eks_managed_node_groups = {
    default = {
      name            = "${var.cluster_name}-nodes"
      instance_types  = [var.node_instance_type]
      desired_size    = var.node_count
      min_size        = var.node_count
      max_size        = var.node_count + 1

      subnet_ids = var.subnet_ids
    }
  }

  tags = {
    Terraform   = "true"
    Environment = var.cluster_name
  }
}
