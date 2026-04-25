variable "region" {
  description = "AWS region for C2 infrastructure"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the C2 VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for C2 subnets"
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

variable "service_port" {
  description = "gRPC port for productcatalogservice (NLB listener port)"
  type        = number
}

variable "node_port" {
  description = "NodePort on EKS workers forwarding to productcatalogservice"
  type        = number
}

variable "allowed_principals" {
  description = "List of AWS principal ARNs allowed to connect to the PrivateLink endpoint service (e.g., C1 AWS account ARN)"
  type        = list(string)
}
