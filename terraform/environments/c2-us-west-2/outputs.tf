output "vpc_id" {
  description = "ID of the C2 VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs in C2"
  value       = module.vpc.private_subnet_ids
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint for C2"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the C2 EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the C2 EKS cluster"
  value       = module.eks.cluster_ca_certificate
}

output "node_security_group_id" {
  description = "Security group ID of C2 EKS worker nodes"
  value       = module.eks.node_security_group_id
}

output "endpoint_service_name" {
  description = "VPC Endpoint Service name for PrivateLink (used by C1 to connect)"
  value       = module.privatelink_provider.endpoint_service_name
}

output "nlb_arn" {
  description = "ARN of the PrivateLink NLB"
  value       = module.privatelink_provider.nlb_arn
}

output "nlb_dns_name" {
  description = "DNS name of the PrivateLink NLB"
  value       = module.privatelink_provider.nlb_dns_name
}
