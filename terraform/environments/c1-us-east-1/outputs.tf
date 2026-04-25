output "vpc_id" {
  description = "ID of the C1 VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs in C1"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs in C1"
  value       = module.vpc.public_subnet_ids
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint for C1"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the C1 EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the C1 EKS cluster"
  value       = module.eks.cluster_ca_certificate
}

output "node_security_group_id" {
  description = "Security group ID of C1 EKS worker nodes"
  value       = module.eks.node_security_group_id
}

output "vpc_endpoint_id" {
  description = "ID of the PrivateLink VPC Endpoint"
  value       = module.privatelink_consumer.vpc_endpoint_id
}

output "vpc_endpoint_dns_name" {
  description = "DNS name of the PrivateLink VPC Endpoint"
  value       = module.privatelink_consumer.vpc_endpoint_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (public entry point)"
  value       = module.alb.alb_dns_name
}

output "target_group_arn" {
  description = "ARN of the ALB target group for frontend"
  value       = module.alb.target_group_arn
}

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = module.waf.web_acl_arn
}
