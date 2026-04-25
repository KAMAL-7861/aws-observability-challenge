output "vpc_endpoint_id" {
  description = "ID of the VPC Endpoint"
  value       = aws_vpc_endpoint.this.id
}

output "vpc_endpoint_dns_name" {
  description = "Primary DNS name of the VPC Endpoint (first DNS entry)"
  value       = try(aws_vpc_endpoint.this.dns_entry[0].dns_name, "")
}

output "endpoint_security_group_id" {
  description = "ID of the security group created for the VPC Endpoint ENIs"
  value       = aws_security_group.endpoint.id
}
