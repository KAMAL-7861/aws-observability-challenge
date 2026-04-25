variable "region" {
  description = "AWS region for C1 infrastructure"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the C1 VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for C1 subnets"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

variable "node_count" {
  description = "Number of EKS worker nodes"
  type        = number
}

variable "c2_endpoint_service_name" {
  description = "VPC Endpoint Service name from C2 (set after C2 is deployed)"
  type        = string
}

variable "c2_service_region" {
  description = "AWS region where the C2 endpoint service is hosted"
  type        = string
}

variable "target_group_port" {
  description = "Port on which the ALB target group receives traffic (frontend service port)"
  type        = number
}

variable "waf_rate_limit" {
  description = "Maximum number of requests allowed from a single IP in a 5-minute window"
  type        = number
}
