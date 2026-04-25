output "endpoint_service_name" {
  description = "Service name of the VPC Endpoint Service (used by consumers to connect)"
  value       = aws_vpc_endpoint_service.this.service_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.nlb.dns_name
}
