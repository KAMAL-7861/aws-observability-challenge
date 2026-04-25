output "cluster_endpoint" {
  description = "Endpoint URL for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA (IAM Roles for Service Accounts)"
  value       = module.eks.oidc_provider_arn
}

output "elastic_agent_role_arn" {
  description = "IAM role ARN for Elastic Agent IRSA — annotate the ServiceAccount with this"
  value       = aws_iam_role.elastic_agent.arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}
